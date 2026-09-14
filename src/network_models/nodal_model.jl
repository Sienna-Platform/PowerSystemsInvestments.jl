# Nodal power balance model: energy balance constraint at each bus (node).
# Structure mirrors multiregion_model.jl but uses PSIP.Node instead of PSIP.Zone.
# Now includes slack variables for infeasible scenarios.

const NODAL_BALANCE_SLACK_PENALTY = 1_000_000.0  # $1M/MWh penalty for power balance violations

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

    # Create slack variables for power balance violations
    jm = get_jump_model(container)
    slack_vars = @variable(jm, nodal_balance_slack[n in nodes, t in time_steps] >= 0)

    # Add constraints with slack: expressions[n, t] == slack[n, t]
    # (slack allows energy imbalance when generation cannot meet demand)
    for t in time_steps, n in nodes
        constraint[n, t] =
            JuMP.@constraint(jm, expressions[n, t] == slack_vars[n, t])
    end

    # Add slack penalty to objective
    current_obj = JuMP.objective_function(jm)
    penalty_cost = sum(slack_vars) * NODAL_BALANCE_SLACK_PENALTY
    JuMP.set_objective(jm, JuMP.MOI.MIN_SENSE, current_obj + penalty_cost)

    return
end
