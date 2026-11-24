_supported_requirement_formulations(::Type{<:PSIP.CapacityReserveMargin}) =
    (RequirementCapacityReserveMargin,)

get_default_attributes(
    ::Type{<:PSIP.CapacityReserveMargin},
    ::Type{RequirementCapacityReserveMargin},
) = Dict{String, Any}("slack_penalty" => REQUIREMENT_SLACK_PENALTY)

# Area of a capacity reserve margin: everything is in the area of a single region model
_reserve_area(p::PSIP.Portfolio, requirement::PSIP.Requirement, ::TransportModel) =
    _requirement_area(p, requirement)
_reserve_area(
    ::PSIP.Portfolio,
    ::PSIP.Requirement,
    ::TransportModel{SingleRegionBalanceModel},
) = nothing

# Variables of a resource located in the area of a capacity reserve margin (a supply
# technology in several regions has one per region)
_names_in_area(technology::PSIP.Technology, ::Nothing) = get_variable_names(technology)
_names_in_area(technology::PSIP.Technology, area::Set{String}) = [
    name for (name, region) in
    zip(get_variable_names(technology), PSIP.get_name.(PSIP.get_region(technology))) if
    region in area
]

# Capacity a technology provides to a capacity reserve margin in each time step of a
# representative period from its variables `names`: supply technologies their installed
# capacity
function _add_reserve_contribution!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    ::Type{D},
    ::PSIP.SupplyTechnology,
    names::Vector{String},
    ::OperationsTechnologyFormulation,
    investment_meta::String,
    ::String,
    op_ix::Int,
) where {D <: PSIP.SupplyTechnology}
    time_mapping = get_time_mapping(container)
    period = get_inverse_invest_mapping(time_mapping)[op_ix]
    capacity = get_expression(container, CumulativeCapacity(), D, investment_meta)
    for t in get_consecutive_slices(time_mapping)[op_ix], name in names
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
    names::Vector{String},
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
    capacity_factors = TimeSeries.values(time_series.data)
    for (ix, t) in enumerate(time_slices), name in names
        JuMP.add_to_expression!(reserve[t], capacity_factors[ix], capacity[name, period])
    end
    return
end

# Storage provides its net injection to the grid
function _add_reserve_contribution!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    ::Type{D},
    ::Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology},
    names::Vector{String},
    ::OperationsTechnologyFormulation,
    ::String,
    operations_meta::String,
    op_ix::Int,
) where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    injection = get_variable(container, ActiveOutPowerVariable(), D, operations_meta)
    withdrawal = get_variable(container, ActiveInPowerVariable(), D, operations_meta)
    for t in get_consecutive_slices(get_time_mapping(container))[op_ix], name in names
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
        [c for c in network.merged_corridors if name in _line_names(c)]
        [c for c in network.new_corridors if c.line.name == name]
        [u for u in network.unit_lines if u.line.name == name]
    ]
end

# Lines dispatched as links outside the PTDF. An AC line in the PTDF without branches (no unit
# can be built) carries no flow.
_is_link(::PTDFNetworkData, ::PSIP.TransmissionTechnology) = true
_is_link(network::PTDFNetworkData, line::PSIP.NodalACTransportTechnology) =
    PSIP.get_name(line) in network.transport_lines

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
        isdisjoint(line_names, _line_names(corridor)) ||
            push!(network.monitored, corridor.name)
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
    controlled = [(line, into) for (line, into) in lines if _is_link(network, line)]
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
    names_to_model_map::Dict{String, TechnologyModel},
    ::Vector{X},
) where {
    T <: PSIP.CapacityReserveMargin,
    B <: RequirementCapacityReserveMargin,
    X <: RequirementModel,
}
    for name in names
        req = PSIP.get_requirement(T, p, name)
        _check_contributors(p, req, names_to_model_map; demands=true)
        _monitor_boundary_corridors!(transport_model, _boundary_lines(p, req; warn=true))
        area = _reserve_area(p, req, transport_model)
        outside = [
            name for resource in _contributing_resources(p, req) for name in
            setdiff(get_variable_names(resource), _names_in_area(resource, area))
        ]
        isempty(outside) ||
            @warn "Resources $(join(outside, ", ")) attached to capacity reserve margin '$name' are outside its area (the regions of its demand technologies), so they do not contribute to it."
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
    con = add_constraints_container!(
        container,
        CapacityReserveMarginConstraint(),
        T,
        PSIP.get_name.(requirements),
        time_steps,
    )
    slacks =
        _add_slack_container!(container, requirements, requirement_model_vector, time_steps)

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
        resource_area = _reserve_area(p, req, transport_model)
        for resource in _contributing_resources(p, req)
            names_in_area = _names_in_area(resource, resource_area)
            isempty(names_in_area) && continue
            tech_model = _contributor_model(names_to_model_map, req_name, resource)
            for op_ix in op_indexes
                _add_reserve_contribution!(
                    reserve,
                    container,
                    get_technology_type(tech_model),
                    resource,
                    names_in_area,
                    get_operations_formulation(tech_model)(),
                    string(get_investment_formulation(tech_model)),
                    string(get_operations_formulation(tech_model)),
                    op_ix,
                )
            end
        end
        for d in _contributing_demands(p, req), op_ix in op_indexes
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            time_slices = consecutive_slices[op_ix]
            for (t, value) in zip(time_slices, TimeSeries.values(time_series.data))
                demand[t] += value
            end
        end

        if get_use_slacks(model)
            cost_factor =
                get_attributes(model)["slack_penalty"] *
                _target_period_cost_factor(container, req)
            for op_ix in op_indexes, t in consecutive_slices[op_ix]
                cost = cost_factor * get_time_step_weight(container, op_ix)
                _add_requirement_slack!(reserve[t], container, slacks, cost, req_name, t)
            end
            # Time steps outside the target period have no constraint
            for t in setdiff(time_steps, keys(reserve))
                slacks[req_name, t] = JuMP.@variable(jump_model)
                JuMP.fix(slacks[req_name, t], 0.0)
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
