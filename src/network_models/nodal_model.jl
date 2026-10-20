# Soft balance at every node: slack_up (unserved energy) and slack_dn (over-supply) are added
# to the node's EnergyBalance, so under the PTDF model they are also located injections.
# Both are penalized in the objective like a variable cost: by the hours of the year each time
# step stands for, over the years of the investment period, discounted to the base year.
function _add_balance_slacks!(
    container::SingleOptimizationContainer,
    ::Type{U},
    nodes::Vector{String},
) where {U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    expressions = get_expression(container, EnergyBalance(), U)
    jump_model = get_jump_model(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    investment_time_stamps = get_investment_time_stamps(time_mapping)
    base_year = get_base_year(container)
    discount_rate = get_discount_rate(container)
    discount_factor = 1.0 / (1.0 + discount_rate)
    years = Dates.value.(Dates.Year.(get_time_stamps(time_mapping)))
    penalty = Dict{Int, Float64}()
    for op_ix in get_operational_indexes(time_mapping)
        inv_tuple = investment_time_stamps[inverse_invest_mapping[op_ix]]
        period_factor = investment_period_annuity_factor(discount_rate, inv_tuple)
        for t in consecutive_slices[op_ix]
            penalty[t] =
                BALANCE_SLACK_PENALTY *
                period_factor *
                get_time_step_weight(container, op_ix) *
                discount_factor^(years[t] - base_year)
        end
    end
    store_names = get_store_variable_names(get_settings(container))
    slack_up = add_variable_container!(container, BalanceSlackUp(), U, nodes, time_steps)
    slack_dn = add_variable_container!(container, BalanceSlackDown(), U, nodes, time_steps)
    for t in time_steps, n in nodes
        up_name = ""
        dn_name = ""
        if store_names
            up_name = "BalanceSlackUp_{$(n), $(t)}"
            dn_name = "BalanceSlackDown_{$(n), $(t)}"
        end
        up = JuMP.@variable(jump_model, lower_bound = 0.0, base_name = up_name)
        dn = JuMP.@variable(jump_model, lower_bound = 0.0, base_name = dn_name)
        slack_up[n, t] = up
        slack_dn[n, t] = dn
        JuMP.add_to_expression!(expressions[n, t], up)
        JuMP.add_to_expression!(expressions[n, t], -1.0, dn)
        add_to_objective_operations_expression!(
            container,
            (up + dn) * get(penalty, t, BALANCE_SLACK_PENALTY),
        )
    end
    return
end

# Nodal power balance model: energy balance constraint at each bus (node).
function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
    use_slacks::Bool=false,
) where {T <: NodalBalanceConstraint, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    nodes = PSIP.get_name.(PSIP.get_regions(PSIP.Node, port))
    use_slacks && _add_balance_slacks!(container, U, nodes)
    expressions = get_expression(container, EnergyBalance(), U)
    constraint = add_constraints_container!(container, T(), U, nodes, time_steps)
    jump_model = get_jump_model(container)
    for t in time_steps, n in nodes
        constraint[n, t] = JuMP.@constraint(jump_model, expressions[n, t] == 0)
    end
    return
end
