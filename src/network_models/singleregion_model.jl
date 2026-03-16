function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: SingleRegionBalanceConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    expressions = get_expression(container, EnergyBalance(), U)
    constraint = add_constraints_container!(container, T(), U, time_steps)
    for t in time_steps
        constraint[t] =
            JuMP.@constraint(get_jump_model(container), expressions[SINGLE_REGION, t] == 0)
    end

    return
end

function add_constraints!(
    container::OptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: SingleRegionBalanceFeasibilityConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    expressions = get_expression(container, FeasibilitySurplus(), U)
    constraint = add_constraints_container!(container, T(), U, time_steps)
    for t in time_steps
        constraint[t] =
            JuMP.@constraint(get_jump_model(container), expressions[SINGLE_REGION, t] >= 0)
    end

    return
end
