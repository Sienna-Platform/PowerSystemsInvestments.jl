_supported_requirement_formulations(::Type{<:PSIP.CapacityReserveMargin}) =
    (RequirementCapacityReserveMargin,)

get_default_attributes(
    ::Type{<:PSIP.CapacityReserveMargin},
    ::Type{RequirementCapacityReserveMargin},
) = Dict{String, Any}("slack_penalty" => REQUIREMENT_SLACK_PENALTY)

# Capacity a technology provides to a capacity reserve margin in each time step of a
# representative period: supply technologies their installed capacity
function _add_reserve_contribution!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.SupplyTechnology,
    ::OperationsTechnologyFormulation,
    investment_meta::String,
    ::String,
    op_ix::Int,
) where {D <: PSIP.SupplyTechnology}
    time_mapping = get_time_mapping(container)
    period = get_inverse_invest_mapping(time_mapping)[op_ix]
    capacity = get_expression(container, CumulativeCapacity(), D, investment_meta)
    for t in get_consecutive_slices(time_mapping)[op_ix],
        name in get_variable_names(technology)

        JuMP.add_to_expression!(reserve[t], capacity[name, period])
    end
    return
end

# Technologies dispatched against a capacity factor provide that share of their capacity
function _add_reserve_contribution!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.SupplyTechnology,
    ::BasicDispatch,
    investment_meta::String,
    ::String,
    op_ix::Int,
) where {D <: PSIP.SupplyTechnology{<:Union{PSY.RenewableDispatch, PSY.HydroDispatch}}}
    time_mapping = get_time_mapping(container)
    period = get_inverse_invest_mapping(time_mapping)[op_ix]
    capacity = get_expression(container, CumulativeCapacity(), D, investment_meta)
    time_slices = get_consecutive_slices(time_mapping)[op_ix]
    time_series = retrieve_ops_time_series(technology, op_ix, time_mapping)
    check_initial_timestamp(
        time_series,
        technology,
        get_time_stamps(time_mapping)[first(time_slices)],
        op_ix,
    )
    capacity_factors = TimeSeries.values(time_series.data)
    for (ix, t) in enumerate(time_slices), name in get_variable_names(technology)
        JuMP.add_to_expression!(reserve[t], capacity_factors[ix], capacity[name, period])
    end
    return
end

# Storage provides its net injection to the grid
function _add_reserve_contribution!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology},
    ::OperationsTechnologyFormulation,
    ::String,
    operations_meta::String,
    op_ix::Int,
) where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    name = PSIP.get_name(technology)
    injection = get_variable(container, ActiveOutPowerVariable(), D, operations_meta)
    withdrawal = get_variable(container, ActiveInPowerVariable(), D, operations_meta)
    for t in get_consecutive_slices(get_time_mapping(container))[op_ix]
        JuMP.add_to_expression!(reserve[t], injection[name, t])
        JuMP.add_to_expression!(reserve[t], -1.0, withdrawal[name, t])
    end
    return
end

# Lines attached to a capacity reserve margin that cross the boundary of its area, and whether
# each ends inside it. The other lines do not contribute.
function _boundary_lines(p::PSIP.Portfolio, requirement::PSIP.Requirement; warn=false)
    area = _requirement_area(p, requirement)
    lines = Tuple{PSIP.TransmissionTechnology, Bool}[]
    for line in _contributing_lines(p, requirement)
        from_inside, to_inside = map(in(area), _arc(line))
        if from_inside == to_inside
            warn &&
                @warn "Line $(PSIP.get_name(line)) is fully $(from_inside ? "inside" : "outside") the area of capacity reserve margin '$(PSIP.get_name(requirement))' (the regions of its demand technologies), so it does not contribute to it."
            continue
        end
        push!(lines, (line, to_inside))
    end
    return lines
end

# PTDF branches that carry the flow of a line
_line_branches(::PTDFNetworkData, ::PSIP.TransmissionTechnology) = []
function _line_branches(network::PTDFNetworkData, line::PSIP.NodalACTransportTechnology)
    name = PSIP.get_name(line)
    return [
        [c for c in network.merged_corridors if name in _names(c)]
        [c for c in network.new_corridors if c.line.name == name]
        [u for u in network.unit_lines if u.line.name == name]
    ]
end

# Under the PTDF model, the corridors of the boundary lines are monitored so that their flows
# are in the model
_monitor_boundary_corridors!(::TransportModel, ::Vector) = nothing
function _monitor_boundary_corridors!(
    transport_model::TransportModel{NodalPTDFModel},
    lines::Vector,
)
    network = get_network_data(transport_model)
    line_names = Set(PSIP.get_name(line) for (line, _) in lines)
    for corridor in network.merged_corridors
        isdisjoint(line_names, _names(corridor)) || push!(network.monitored, corridor.name)
    end
    return
end

# Net flow into the area of a controlled line: its flow towards the area
function _add_line_inflow!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    ::Type{D},
    line::PSIP.TransmissionTechnology,
    ::BasicDispatch,
    into_area::Bool,
    ::String,
    operations_meta::String,
    op_ix::Int,
) where {D <: PSIP.TransmissionTechnology}
    flow = get_variable(container, FlowActivePowerVariable(), D, operations_meta)
    name = PSIP.get_name(line)
    for t in get_consecutive_slices(get_time_mapping(container))[op_ix]
        JuMP.add_to_expression!(reserve[t], into_area ? 1.0 : -1.0, flow[name, t])
    end
    return
end

# With losses, the flow towards the area arrives net of its losses, and the terminal inside
# the area bears half the constant losses
function _add_line_inflow!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    ::Type{D},
    line::PSIP.TransmissionTechnology,
    ::BasicDispatchWithLosses,
    into_area::Bool,
    investment_meta::String,
    operations_meta::String,
    op_ix::Int,
) where {D <: ControllableTransportTechnology}
    time_mapping = get_time_mapping(container)
    period = get_inverse_invest_mapping(time_mapping)[op_ix]
    from_to = get_variable(container, FlowActivePowerFromToVariable(), D, operations_meta)
    to_from = get_variable(container, FlowActivePowerToFromVariable(), D, operations_meta)
    toward, away = into_area ? (from_to, to_from) : (to_from, from_to)
    capacity = get_expression(container, CumulativeCapacity(), D, investment_meta)
    rate, constant = _loss_terms(line)
    name = PSIP.get_name(line)
    for t in get_consecutive_slices(time_mapping)[op_ix]
        JuMP.add_to_expression!(reserve[t], 1.0 - rate, toward[name, t])
        JuMP.add_to_expression!(reserve[t], -1.0, away[name, t])
        JuMP.add_to_expression!(reserve[t], -constant / 2, capacity[name, period])
    end
    return
end

function _add_controlled_line_inflows!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    lines::Vector,
    names_to_model_map::Dict{String, TechnologyModel},
    req_name::String,
    op_ix::Int,
)
    for (line, into_area) in lines
        tech_model = _contributor_model(names_to_model_map, req_name, line)
        _add_line_inflow!(
            reserve,
            container,
            get_technology_type(tech_model),
            line,
            get_operations_formulation(tech_model)(),
            into_area,
            string(get_investment_formulation(tech_model)),
            string(get_operations_formulation(tech_model)),
            op_ix,
        )
    end
    return
end

_add_line_inflows!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    lines::Vector,
    names_to_model_map::Dict{String, TechnologyModel},
    req_name::String,
    ::TransportModel,
    ::Set{String},
    op_ix::Int,
) = _add_controlled_line_inflows!(
    reserve,
    container,
    lines,
    names_to_model_map,
    req_name,
    op_ix,
)

# Under the PTDF model, AC lines contribute the flows of their branches, each branch once even
# when several of its lines are attached
function _add_line_inflows!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    lines::Vector,
    names_to_model_map::Dict{String, TechnologyModel},
    req_name::String,
    transport_model::TransportModel{NodalPTDFModel},
    area::Set{String},
    op_ix::Int,
)
    network = get_network_data(transport_model)
    branches = unique(
        b -> b.name,
        [b for (line, _) in lines for b in _line_branches(network, line)],
    )
    flow = get_expression(container, PTDFBranchFlow(), PSIP.Portfolio)
    for branch in branches, t in get_consecutive_slices(get_time_mapping(container))[op_ix]
        JuMP.add_to_expression!(
            reserve[t],
            last(branch.arc) in area ? 1.0 : -1.0,
            flow[branch.name, t],
        )
    end
    controlled =
        [(line, into) for (line, into) in lines if isempty(_line_branches(network, line))]
    _add_controlled_line_inflows!(
        reserve,
        container,
        controlled,
        names_to_model_map,
        req_name,
        op_ix,
    )
    return
end

function construct_requirement!(
    ::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::Type{T},
    ::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    ::Dict{String, TechnologyModel},
    ::Vector{X},
) where {
    T <: PSIP.CapacityReserveMargin,
    B <: RequirementCapacityReserveMargin,
    X <: RequirementModel,
}
    for name in names
        req = PSIP.get_requirement(T, p, name)
        _check_contributors(p, req; demands=true)
        _monitor_boundary_corridors!(transport_model, _boundary_lines(p, req; warn=true))
    end
    return
end

function construct_requirement!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    ::Type{T},
    ::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    names_to_model_map::Dict{String, TechnologyModel},
    requirement_model_vector::Vector{X},
) where {
    T <: PSIP.CapacityReserveMargin,
    B <: RequirementCapacityReserveMargin,
    X <: RequirementModel,
}
    requirements = [PSIP.get_requirement(T, p, n) for n in names]
    add_constraints!(
        container,
        CapacityReserveMarginConstraint(),
        p,
        requirements,
        B(),
        names_to_model_map,
        requirement_model_vector,
        transport_model,
    )
    return
end

# In each time step of the target period: contributions + slack >=
# (1 + capacity_reserve_fraction) * demand. Other time steps have no constraint, and their
# slacks are fixed at 0.
function add_constraints!(
    container::SingleOptimizationContainer,
    ::CapacityReserveMarginConstraint,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    ::RequirementCapacityReserveMargin,
    names_to_model_map::Dict{String, TechnologyModel},
    requirement_model_vector::Vector{X},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {T <: PSIP.CapacityReserveMargin, X <: RequirementModel}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    map_to_op = get_investment_map_to_operational_slices(time_mapping)
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    demand_expression = get_expression(container, DemandExpression(), PSIP.Portfolio)

    con = add_constraints_container!(
        container,
        CapacityReserveMarginConstraint(),
        T,
        PSIP.get_name.(requirements),
        time_steps,
    )
    slack_names = [
        PSIP.get_name(req) for
        (req, model) in zip(requirements, requirement_model_vector) if get_use_slacks(model)
    ]
    slacks = if isempty(slack_names)
        nothing
    else
        add_variable_container!(
            container,
            RequirementSlackVariable(),
            T,
            slack_names,
            time_steps,
        )
    end

    for (req, model) in zip(requirements, requirement_model_vector)
        req_name = PSIP.get_name(req)
        op_indexes = map_to_op[_target_investment_period(time_mapping, req)]
        reserve = Dict(
            t => JuMP.AffExpr(0.0) for op_ix in op_indexes for
            t in consecutive_slices[op_ix]
        )
        demand = Dict(t => 0.0 for t in keys(reserve))
        area = _requirement_area(p, req)
        lines = _boundary_lines(p, req)
        for op_ix in op_indexes
            _add_line_inflows!(
                reserve,
                container,
                lines,
                names_to_model_map,
                req_name,
                transport_model,
                area,
                op_ix,
            )
        end
        for resource in _contributing_resources(p, req)
            tech_model = _contributor_model(names_to_model_map, req_name, resource)
            for op_ix in op_indexes
                _add_reserve_contribution!(
                    reserve,
                    container,
                    get_technology_type(tech_model),
                    resource,
                    get_operations_formulation(tech_model)(),
                    string(get_investment_formulation(tech_model)),
                    string(get_operations_formulation(tech_model)),
                    op_ix,
                )
            end
        end
        for d in _contributing_demands(p, req)
            for t in keys(demand)
                demand[t] += JuMP.constant(demand_expression[PSIP.get_name(d), t])
            end
            # Price-responsive demand counts as capacity; involuntary shedding does not
            _add_unserved_demand!(
                t -> reserve[t],
                container,
                d,
                _demand_formulation(names_to_model_map, d),
                keys(reserve),
                1.0;
                credited=true,
            )
        end

        if req_name in slack_names
            cost_factor =
                get_attributes(model)["slack_penalty"] *
                _target_period_cost_factor(container, req)
            for t in time_steps
                slacks[req_name, t] = JuMP.@variable(
                    jump_model,
                    lower_bound = 0.0,
                    base_name =
                        store_names ? "RequirementSlackVariable_{$(req_name), $(t)}" : "",
                )
                haskey(reserve, t) || JuMP.fix(slacks[req_name, t], 0.0; force=true)
            end
            for op_ix in op_indexes, t in consecutive_slices[op_ix]
                JuMP.add_to_expression!(reserve[t], slacks[req_name, t])
                add_to_objective_operations_expression!(
                    container,
                    cost_factor *
                    get_time_step_weight(container, op_ix) *
                    slacks[req_name, t],
                )
            end
        end

        margin = 1.0 + PSIP.get_capacity_reserve_fraction(req)
        for (t, contribution) in reserve
            con[req_name, t] =
                JuMP.@constraint(jump_model, contribution >= margin * demand[t])
        end
    end
    return
end
