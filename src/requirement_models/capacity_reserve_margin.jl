_supported_requirement_formulations(::Type{<:PSIP.CapacityReserveMargin}) =
    (RequirementCapacityReserveMargin,)

get_default_attributes(
    ::Type{<:PSIP.CapacityReserveMargin},
    ::Type{RequirementCapacityReserveMargin},
) = Dict{String, Any}("slack_penalty" => REQUIREMENT_SLACK_PENALTY)

# Regions (or nodes) of a reserve margin's demands; nothing (everything) in a single region
_reserve_area(p::PSIP.Portfolio, requirement::PSIP.Requirement, ::TransportModel) = Set(
    PSIP.get_name(region) for d in _contributing_demands(p, requirement) for
    region in PSIP.get_region(d)
)
_reserve_area(
    ::PSIP.Portfolio,
    ::PSIP.Requirement,
    ::TransportModel{SingleRegionBalanceModel},
) = nothing

# Variables of a resource in the area (one per region for supply in several regions)
_names_in_area(technology::PSIP.Technology, ::Nothing) = get_variable_names(technology)
_names_in_area(technology::PSIP.Technology, area::Set{String}) = [
    name for (name, region) in
    zip(get_variable_names(technology), PSIP.get_name.(PSIP.get_region(technology))) if
    region in area
]

# Reserve from the variables `names` of a technology: supply its installed capacity
function _add_reserve_contribution!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    ::PSIP.SupplyTechnology,
    names::Vector{String},
    tech_model::TechnologyModel{D},
    op_ix::Int,
) where {D <: PSIP.SupplyTechnology}
    time_mapping = get_time_mapping(container)
    period = get_inverse_invest_mapping(time_mapping)[op_ix]
    meta = string(get_investment_formulation(tech_model))
    capacity = get_expression(container, CumulativeCapacity(), D, meta)
    for t in get_consecutive_slices(time_mapping)[op_ix], name in names
        JuMP.add_to_expression!(reserve[t], capacity[name, period])
    end
    return
end

# Technologies dispatched against a capacity factor provide that share of their capacity
function _add_reserve_contribution!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    technology::PSIP.SupplyTechnology,
    names::Vector{String},
    tech_model::TechnologyModel{D, <:Any, BasicDispatch},
    op_ix::Int,
) where {D <: PSIP.SupplyTechnology{<:Union{PSY.RenewableDispatch, PSY.HydroDispatch}}}
    time_mapping = get_time_mapping(container)
    period = get_inverse_invest_mapping(time_mapping)[op_ix]
    meta = string(get_investment_formulation(tech_model))
    capacity = get_expression(container, CumulativeCapacity(), D, meta)
    time_series = retrieve_ops_time_series(technology, op_ix, time_mapping)
    capacity_factors = TimeSeries.values(time_series.data)
    for (ix, t) in enumerate(get_consecutive_slices(time_mapping)[op_ix]), name in names
        JuMP.add_to_expression!(reserve[t], capacity_factors[ix], capacity[name, period])
    end
    return
end

# Storage provides its net injection to the grid
function _add_reserve_contribution!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    ::Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology},
    names::Vector{String},
    tech_model::TechnologyModel,
    op_ix::Int,
)
    for t in get_consecutive_slices(get_time_mapping(container))[op_ix], name in names
        _add_net_injection!(reserve[t], container, tech_model, name, t)
    end
    return
end

# Attached lines crossing the area's boundary, with whether each ends inside it
function _boundary_lines(
    p::PSIP.Portfolio,
    requirement::PSIP.Requirement,
    area::Set{String};
    warn=false,
)
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

# Lines have no effect in a single region model
function _boundary_lines(
    p::PSIP.Portfolio,
    requirement::PSIP.Requirement,
    ::Nothing;
    warn=false,
)
    warn && _warn_ignored_contributors(
        _contributing_lines(p, requirement),
        requirement,
        "Lines",
    )
    return Tuple{PSIP.TransmissionTechnology, Bool}[]
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

# Lines dispatched outside the PTDF (an AC line in it without branches carries no flow)
_is_link(::PTDFNetworkData, ::PSIP.TransmissionTechnology) = true
_is_link(network::PTDFNetworkData, line::PSIP.NodalACTransportTechnology) =
    PSIP.get_name(line) in network.transport_lines

# Monitors the corridors of the boundary lines so that their flows are in the model
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
function _add_link_inflow!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    line::PSIP.TransmissionTechnology,
    into_area::Bool,
    tech_model::TechnologyModel{D, <:Any, BasicDispatch},
    op_ix::Int,
) where {D <: PSIP.TransmissionTechnology}
    meta = string(get_operations_formulation(tech_model))
    flow = get_variable(container, FlowActivePowerVariable(), D, meta)
    name = PSIP.get_name(line)
    for t in get_consecutive_slices(get_time_mapping(container))[op_ix]
        JuMP.add_to_expression!(reserve[t], into_area ? 1.0 : -1.0, flow[name, t])
    end
    return
end

# Inflow net of its losses; the terminal in the area bears half the constant losses
function _add_link_inflow!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    line::PSIP.TransmissionTechnology,
    into_area::Bool,
    tech_model::TechnologyModel{D, <:Any, BasicDispatchWithLosses},
    op_ix::Int,
) where {D <: ControllableTransportTechnology}
    time_mapping = get_time_mapping(container)
    period = get_inverse_invest_mapping(time_mapping)[op_ix]
    meta = string(get_operations_formulation(tech_model))
    from_to = get_variable(container, FlowActivePowerFromToVariable(), D, meta)
    to_from = get_variable(container, FlowActivePowerToFromVariable(), D, meta)
    toward, away = into_area ? (from_to, to_from) : (to_from, from_to)
    investment_meta = string(get_investment_formulation(tech_model))
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

function _add_link_inflows!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    lines::Vector,
    names_to_model_map::Dict{String, TechnologyModel},
    req_name::String,
    op_ix::Int,
)
    for (line, into_area) in lines
        tech_model = _contributor_model(names_to_model_map, req_name, line)
        _add_link_inflow!(reserve, container, line, into_area, tech_model, op_ix)
    end
    return
end

_add_boundary_inflows!(
    reserve::Dict{Int, JuMP.AffExpr},
    container::SingleOptimizationContainer,
    lines::Vector,
    names_to_model_map::Dict{String, TechnologyModel},
    req_name::String,
    ::TransportModel,
    ::Union{Nothing, Set{String}},
    op_ix::Int,
) = _add_link_inflows!(reserve, container, lines, names_to_model_map, req_name, op_ix)

# AC lines contribute the flows of their PTDF branches, each branch once
function _add_boundary_inflows!(
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
    _add_link_inflows!(reserve, container, controlled, names_to_model_map, req_name, op_ix)
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
        area = _reserve_area(p, req, transport_model)
        _monitor_boundary_corridors!(
            transport_model,
            _boundary_lines(p, req, area; warn=true),
        )
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

# In each step of the target period: contributions + slack >= (1 + fraction) * demand
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
        period = _target_investment_period(time_mapping, req)
        op_indexes = map_to_op[period]
        reserve = Dict(
            t => JuMP.AffExpr(0.0) for op_ix in op_indexes for
            t in consecutive_slices[op_ix]
        )
        area = _reserve_area(p, req, transport_model)
        lines = _boundary_lines(p, req, area)
        for op_ix in op_indexes
            _add_boundary_inflows!(
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
            names_in_area = _names_in_area(resource, area)
            isempty(names_in_area) && continue
            tech_model = _contributor_model(names_to_model_map, req_name, resource)
            for op_ix in op_indexes
                _add_reserve_contribution!(
                    reserve,
                    container,
                    resource,
                    names_in_area,
                    tech_model,
                    op_ix,
                )
            end
        end
        if get_use_slacks(model)
            cost_factor =
                get_attributes(model)["slack_penalty"] *
                _period_cost_factor(container, period)
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
        for op_ix in op_indexes
            demand = _requirement_demand(p, req, time_mapping, op_ix)
            for (ix, t) in enumerate(consecutive_slices[op_ix])
                con[req_name, t] =
                    JuMP.@constraint(jump_model, reserve[t] >= margin * demand[ix])
            end
        end
    end
    return
end
