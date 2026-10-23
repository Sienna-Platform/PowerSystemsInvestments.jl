_is_resource(::PSIP.Technology) = false
_is_resource(::PSIP.ResourceTechnology) = true
_is_demand(::PSIP.Technology) = false
_is_demand(::PSIP.DemandTechnology) = true

"""
Return the available technologies attached to `requirement` that participate on
the generation side — `PSIP.ResourceTechnology` subtypes (`SupplyTechnology`,
`StorageTechnology`, `ColocatedSupplyStorageTechnology`). Generic over any
`PSIP.Requirement` so it is shared by all requirement models.
"""
function _contributing_resources(p::PSIP.Portfolio, requirement::PSIP.Requirement)
    return [
        t for t in PSIP.get_contributing_technologies(p, requirement) if
        _is_resource(t) && PSIP.get_available(t)
    ]
end

"""
Return the available technologies attached to `requirement` that participate on
the demand side — `PSIP.DemandTechnology` subtypes (`DemandRequirement`,
`DemandSideTechnology`). Generic over any `PSIP.Requirement`.
"""
function _contributing_demands(p::PSIP.Portfolio, requirement::PSIP.Requirement)
    return [
        t for t in PSIP.get_contributing_technologies(p, requirement) if
        _is_demand(t) && PSIP.get_available(t)
    ]
end

# Shortfall variables of the requirements whose model uses slacks. A unit of shortfall in a
# target period costs the "slack_penalty" in every year of that period.
function _add_requirement_slacks!(
    container::SingleOptimizationContainer,
    requirements::Vector{T},
    requirement_model_vector::Vector{<:RequirementModel},
) where {T <: PSIP.Requirement}
    with_slacks = [
        (req, model) for (req, model) in zip(requirements, requirement_model_vector) if
        get_use_slacks(model)
    ]
    isempty(with_slacks) && return
    time_mapping = get_time_mapping(container)
    investment_time_stamps = get_investment_time_stamps(time_mapping)
    discount_rate = get_discount_rate(container)
    base_year = get_base_year(container)
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    slacks = add_variable_container!(
        container,
        RequirementSlackVariable(),
        T,
        [PSIP.get_name(req) for (req, _) in with_slacks],
    )
    for (req, model) in with_slacks
        name = PSIP.get_name(req)
        slacks[name] = JuMP.@variable(
            jump_model,
            lower_bound = 0.0,
            base_name = store_names ? "RequirementSlackVariable_{$(name)}" : "",
        )
        inv_tuple = investment_time_stamps[_target_investment_period(time_mapping, req)]
        cost =
            get_attributes(model)["slack_penalty"] *
            investment_period_annuity_factor(discount_rate, inv_tuple) *
            (1.0 + discount_rate)^(base_year - Dates.year(first(inv_tuple)))
        add_to_objective_operations_expression!(container, cost * slacks[name])
    end
    return
end

# Stores the duals of the constraints listed by the requirement models
function _add_requirement_duals!(
    container::SingleOptimizationContainer,
    ::Type{T},
    requirement_model_vector::Vector{<:RequirementModel},
) where {T <: PSIP.Requirement}
    constraints = get_constraints(container)
    for model in requirement_model_vector, constraint_type in get_duals(model)
        key = ConstraintKey(constraint_type, T)
        if !haskey(constraints, key)
            error("$(nameof(T)) has no $(nameof(constraint_type)) to take the duals of.")
        end
        container.duals[key] = constraints[key]
    end
    return
end
