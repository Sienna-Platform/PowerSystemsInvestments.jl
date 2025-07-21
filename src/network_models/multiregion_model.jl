function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: MultiRegionBalanceConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    regions = PSIP.get_name.(PSIP.get_regions(PSIP.Zone, port))
    expressions = get_expression(container, EnergyBalance(), U)
    constraint = add_constraints_container!(container, T(), U, regions, time_steps)
    for t in time_steps, r in regions
        constraint[r, t] =
            JuMP.@constraint(get_jump_model(container), expressions[r, t] == 0)
    end

    return
end
