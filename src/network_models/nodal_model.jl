# Nodal power balance model: energy balance constraint at each bus (node).
function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: NodalBalanceConstraint, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    nodes = PSY.get_name.(PSIP.get_model_topologies(port, PSY.ACBus))
    expressions = get_expression(container, EnergyBalance(), U)
    constraint = add_constraints_container!(container, T(), U, nodes, time_steps)
    jump_model = get_jump_model(container)
    for t in time_steps, n in nodes
        constraint[n, t] = JuMP.@constraint(jump_model, expressions[n, t] == 0)
    end
    return
end
