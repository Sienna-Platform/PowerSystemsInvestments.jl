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

    jm = get_jump_model(container)

    # Check if nodal slack is enabled (can be toggled via command line)
    enable_nodal_slack = try
        Main.ENABLE_NODAL_SLACK
    catch
        true
    end

    if enable_nodal_slack
        # Create positive and negative slack variables to handle both over- and under-supply
        slack_pos = @variable(jm, nodal_balance_slack_pos[n in nodes, t in time_steps] >= 0)
        slack_neg = @variable(jm, nodal_balance_slack_neg[n in nodes, t in time_steps] >= 0)

        # Add constraints with slack: expressions[n, t] == slack_pos[n, t] - slack_neg[n, t]
        # This allows slack to be positive (over-supply) or negative (under-supply)
        for t in time_steps, n in nodes
            constraint[n, t] =
                JuMP.@constraint(jm, expressions[n, t] == slack_pos[n, t] - slack_neg[n, t])
        end

        # Store slack variables for penalty accumulation
        # NOTE: Objective is set in reserve margin function to accumulate all slack penalties
        jm.ext[:nodal_balance_slack_pos] = slack_pos
        jm.ext[:nodal_balance_slack_neg] = slack_neg
    else
        # Hard constraints (original behavior)
        for t in time_steps, n in nodes
            constraint[n, t] =
                JuMP.@constraint(jm, expressions[n, t] == 0)
        end
    end

    return
end
