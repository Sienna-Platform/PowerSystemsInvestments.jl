# Nodal power balance model: energy balance constraint at each bus (node).
# Structure mirrors multiregion_model.jl but balances buses (nodes) instead of zones.
# Now includes slack variables for infeasible scenarios.

const NODAL_BALANCE_SLACK_PENALTY = 1_000_000.0  # $1M/MWh penalty for power balance violations

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: NodalBalanceConstraint, U <: PSIP.Portfolio}
    @info "[NodalModel] Building NodalBalanceConstraint"

    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    nodes = PSY.get_name.(get_nodes(port))
    expressions = get_expression(container, EnergyBalance(), U)
    constraint = add_constraints_container!(container, T(), U, nodes, time_steps)

    jm = get_jump_model(container)

    # Check if nodal slack is enabled (can be toggled via command line)
    enable_nodal_slack = try
        Main.ENABLE_NODAL_SLACK
    catch
        true
    end

    @info "[NodalModel] enable_nodal_slack=$enable_nodal_slack, nodes=$(length(nodes)), timesteps=$(length(time_steps))"

    if enable_nodal_slack
        # Create positive and negative slack variables to handle both over- and under-supply
        @info "[NodalModel] Creating nodal slack variables..."
        slack_pos = @variable(jm, nodal_balance_slack_pos[n in nodes, t in time_steps] >= 0)
        slack_neg = @variable(jm, nodal_balance_slack_neg[n in nodes, t in time_steps] >= 0)
        @info "[NodalModel] Created $(length(nodes) * length(time_steps)) slack_pos and slack_neg variables"

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
        @info "[NodalModel] Stored slack variables in jm.ext"
    else
        # Hard constraints (original behavior)
        for t in time_steps, n in nodes
            constraint[n, t] =
                JuMP.@constraint(jm, expressions[n, t] == 0)
        end
    end

    return
end

# Capacity adequacy constraint for nodal model (same as single-region)
function add_constraints!(
    _container::SingleOptimizationContainer,
    ::Type{T},
    _port::U,
) where {T <: CapacityAdequacyConstraint, U <: PSIP.Portfolio}
    # Note: This constraint is registered but intentionally does nothing during build.
    # The capacity adequacy constraint is enforced through the energy balance and
    # capacity requirements of individual technologies. The framework handles this
    # automatically through:
    # 1. TechnologyFinancialData.investment_limits setting maximum investment
    # 2. ActivePowerLimitsConstraint ensuring dispatch ≤ installed capacity
    # 3. CumulativeCapacity variables tracking built capacity over time
    #
    # If custom capacity adequacy logic with non-unity capacity credits is needed,
    # it should be implemented at a different point in the build process after
    # all variables have been created.
    return
end
