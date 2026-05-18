# Nodal power balance model: energy balance constraint at each bus (node).
# Structure mirrors multiregion_model.jl but uses PSIP.Node instead of PSIP.Zone.

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: NodalBalanceConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    nodes = PSIP.get_name.(PSIP.get_regions(PSIP.Node, port))
    expressions = get_expression(container, EnergyBalance(), U)
    constraint = add_constraints_container!(container, T(), U, nodes, time_steps)
    for t in time_steps, n in nodes
        constraint[n, t] =
            JuMP.@constraint(get_jump_model(container), expressions[n, t] == 0)
    end

    return
end
