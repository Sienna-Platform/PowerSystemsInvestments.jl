const CapacityRequirements =
    Union{PSIP.MinimumCapacityRequirements, PSIP.MaximumCapacityRequirements}

_supported_requirement_formulations(::Type{<:PSIP.MinimumCapacityRequirements}) =
    (RequirementMinimumCapacity,)
_supported_requirement_formulations(::Type{<:PSIP.MaximumCapacityRequirements}) =
    (RequirementMaximumCapacity,)

get_default_attributes(
    ::Type{<:CapacityRequirements},
    ::Type{<:Union{RequirementMinimumCapacity, RequirementMaximumCapacity}},
) = Dict{String, Any}("slack_penalty" => CAPACITY_REQUIREMENT_SLACK_PENALTY)

# Capacity a resource counts towards a capacity requirement in an investment period
function _add_requirement_capacity!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.SupplyTechnology,
    investment_meta::String,
    period::Int,
) where {D <: PSIP.SupplyTechnology}
    capacity = get_expression(container, CumulativeCapacity(), D, investment_meta)
    for name in get_variable_names(technology)
        JuMP.add_to_expression!(expression, capacity[name, period])
    end
    return
end

function _add_requirement_capacity!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.StorageTechnology,
    investment_meta::String,
    period::Int,
) where {D <: PSIP.StorageTechnology}
    capacity = get_expression(container, CumulativePowerCapacity(), D, investment_meta)
    JuMP.add_to_expression!(expression, capacity[PSIP.get_name(technology), period])
    return
end

# Co-located technologies count their wind and solar capacity
function _add_requirement_capacity!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.ColocatedSupplyStorageTechnology,
    investment_meta::String,
    period::Int,
) where {D <: PSIP.ColocatedSupplyStorageTechnology}
    for expression_type in (CumulativeWindCapacity(), CumulativeSolarCapacity())
        capacity = get_expression(container, expression_type, D, investment_meta)
        JuMP.add_to_expression!(expression, capacity[PSIP.get_name(technology), period])
    end
    return
end

_capacity_constraint(
    jump_model::JuMP.Model,
    requirement::PSIP.MinimumCapacityRequirements,
    capacity::JuMP.AffExpr,
    slack::JuMP.AffExpr,
) = JuMP.@constraint(jump_model, capacity + slack >= PSIP.get_min_capacity_mw(requirement))
_capacity_constraint(
    jump_model::JuMP.Model,
    requirement::PSIP.MaximumCapacityRequirements,
    capacity::JuMP.AffExpr,
    slack::JuMP.AffExpr,
) = JuMP.@constraint(jump_model, capacity - slack <= PSIP.get_max_capacity_mw(requirement))

function construct_requirement!(
    ::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::Type{T},
    ::Type{B},
    ::TransportModel{<:AbstractTransportAggregation},
    names_to_model_map::Dict{String, TechnologyModel},
    ::Vector{X},
) where {
    T <: CapacityRequirements,
    B <: Union{RequirementMinimumCapacity, RequirementMaximumCapacity},
    X <: RequirementModel,
}
    for name in names
        req = PSIP.get_requirement(T, p, name)
        _check_contributors(p, req, names_to_model_map; demands=false)
        _warn_ignored_contributors(_contributing_lines(p, req), req, "Lines")
        _warn_ignored_contributors(
            _contributing_demands(p, req),
            req,
            "Demand technologies",
        )
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
    ::TransportModel{<:AbstractTransportAggregation},
    names_to_model_map::Dict{String, TechnologyModel},
    requirement_model_vector::Vector{X},
) where {
    T <: CapacityRequirements,
    B <: Union{RequirementMinimumCapacity, RequirementMaximumCapacity},
    X <: RequirementModel,
}
    requirements = [PSIP.get_requirement(T, p, n) for n in names]
    add_constraints!(
        container,
        CapacityRequirementConstraint(),
        p,
        requirements,
        B(),
        names_to_model_map,
        requirement_model_vector,
    )
    return
end

# Capacity of the resources in the target period + slack >= min_capacity_mw, or - slack <=
# max_capacity_mw
function add_constraints!(
    container::SingleOptimizationContainer,
    ::CapacityRequirementConstraint,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    ::B,
    names_to_model_map::Dict{String, TechnologyModel},
    requirement_model_vector::Vector{X},
) where {
    T <: CapacityRequirements,
    B <: Union{RequirementMinimumCapacity, RequirementMaximumCapacity},
    X <: RequirementModel,
}
    time_mapping = get_time_mapping(container)
    jump_model = get_jump_model(container)
    slacks = _add_slack_container!(container, requirements, requirement_model_vector)
    con = add_constraints_container!(
        container,
        CapacityRequirementConstraint(),
        T,
        PSIP.get_name.(requirements),
    )
    for (req, model) in zip(requirements, requirement_model_vector)
        req_name = PSIP.get_name(req)
        period = _target_investment_period(time_mapping, req)
        capacity = JuMP.AffExpr(0.0)
        for resource in _contributing_resources(p, req)
            tech_model = _contributor_model(names_to_model_map, req_name, resource)
            _add_requirement_capacity!(
                capacity,
                container,
                get_technology_type(tech_model),
                resource,
                string(get_investment_formulation(tech_model)),
                period,
            )
        end
        slack = JuMP.AffExpr(0.0)
        if get_use_slacks(model)
            cost =
                get_attributes(model)["slack_penalty"] *
                _target_period_cost_factor(container, req)
            _add_requirement_slack!(slack, container, slacks, cost, req_name)
        end
        con[req_name] = _capacity_constraint(jump_model, req, capacity, slack)
    end
    return
end
