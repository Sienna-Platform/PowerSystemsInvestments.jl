############ FOR REFERENCE #####################

# The methods for adding to the objective function are:
# objective_function! is dispatched for technology type and formulations
# objective_function! calls add_variable_cost!, or add_capital_cost! or add_fixed_om_cost!
# add_variable_cost!, add_capital_cost! and add_fixed_om_cost! calls _add_cost_to_objective!
# _add_cost_to_objective! based on the VariableType and CostType calls _add_linearcurve_cost!
# _add_linearcurve_cost! transform cost terms, via amortized lump sums and net-present value to base year
# _add_linearcurve_cost! calls _add_linearcurve_variable_term_to_model!
# _add_linearcurve_variable_term_to_model! calls _add_proportional_term! to add terms to objective function
# _add_linearcurve_variable_term_to_model! also calls add_to_expression to add terms to Cost Expressions
# _add_proportional_term! calls add_to_objective_operations_expression! to add operation costs to objective function (using JuMP)
# _add_proportional_term! calls add_to_objective_investment_expression! to add capital terms to objective function (using JuMP)

################################################

"""
Adds to the cost function cost terms for sum of variables with common factor to be used for cost expression for optimization_container model.

# Arguments

  - container::OptimizationContainer : the optimization_container model built in PowerSimulations
  - var_key::VariableKey: The variable name
  - technology_name::String: The technology_name of the variable container
  - cost_component::PSY.CostCurve{PSY.LinearCurve} : container for cost to be associated with variable
"""
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    value_curve::IS.ValueCurve,
    ::U,
    tech_model::String;
    interconnection_cost::Float64=0.0,
) where {T <: VariableType, U <: AbstractTechnologyFormulation}
    cost_component = PSY.get_function_data(value_curve)
    # Overnight capital and last-mile interconnection costs are both in \$/MW,
    # so the interconnection term is added directly to the proportional term.
    # Costs are per MW, so they are scaled by the capacity that one unit of the variable adds.
    proportional_term =
        (PSY.get_proportional_term(cost_component) + interconnection_cost) *
        get_variable_multiplier(T(), technology, U())
    @debug "Cost is assumed to be in natural units: \$/MWh"
    multiplier = objective_function_multiplier(T(), U())
    _add_linearcurve_cost!(
        container,
        T(),
        technology,
        value_curve,
        multiplier * proportional_term,
        tech_model,
    )
    return
end

#Fixed OM calculated from cumulative capacity
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {T <: CumulativeInvestmentExpressionType, U <: AbstractTechnologyFormulation}
    proportional_term = PSY.get_fixed(om_cost)
    multiplier = objective_function_multiplier(T(), U())
    _add_linearcurve_cost!(
        container,
        T(),
        technology,
        om_cost,
        multiplier * proportional_term,
        tech_model,
    )
    return
end

#Variable OM from dispatch
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {T <: OperationsVariableType, U <: AbstractTechnologyFormulation}
    _add_variable_cost_to_objective!(
        container,
        T(),
        technology,
        om_cost,
        PSY.get_variable(om_cost),
        U(),
        tech_model,
    )
    return
end

function _add_variable_cost_to_objective!(
    ::SingleOptimizationContainer,
    ::OperationsVariableType,
    ::PSIP.Technology,
    ::PSY.OperationalCost,
    cost_curve::PSY.ProductionVariableCostCurve,
    ::AbstractTechnologyFormulation,
    ::String,
)
    throw_unsupported_curve(cost_curve)
    return
end

function _add_variable_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    cost_curve::PSY.CostCurve{PSY.LinearCurve},
    ::U,
    tech_model::String,
) where {T <: OperationsVariableType, U <: AbstractTechnologyFormulation}
    proportional_term =
        PSY.get_proportional_term(PSY.get_value_curve(cost_curve)) +
        PSY.get_proportional_term(PSY.get_vom_cost(cost_curve))
    multiplier = objective_function_multiplier(T(), U())
    _add_linearcurve_cost!(
        container,
        T(),
        technology,
        om_cost,
        multiplier * proportional_term,
        tech_model,
    )
    return
end

function _add_variable_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    fuel_curve::PSY.FuelCurve{PSY.LinearCurve},
    ::U,
    tech_model::String,
) where {T <: OperationsVariableType, U <: AbstractTechnologyFormulation}
    multiplier = objective_function_multiplier(T(), U())
    fuel_term = get_heat_rate(fuel_curve) * get_fuel_price(fuel_curve)
    _add_linearcurve_cost!(
        container,
        T(),
        FuelCost(),
        technology,
        om_cost,
        multiplier * fuel_term,
        tech_model,
    )
    vom_term = PSY.get_proportional_term(PSY.get_vom_cost(fuel_curve))
    if !iszero(vom_term)
        _add_linearcurve_cost!(
            container,
            T(),
            VariableOMCost(),
            technology,
            om_cost,
            multiplier * vom_term,
            tech_model,
        )
    end
    return
end

#Storage Charge cost
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {
    T <: Union{ActiveInPowerVariable, ActivePowerChargeVariable},
    U <: AbstractTechnologyFormulation,
}
    _add_variable_cost_to_objective!(
        container,
        T(),
        technology,
        om_cost,
        PSY.get_charge_variable_cost(om_cost),
        U(),
        tech_model,
    )
    return
end

#Storage Discharge cost
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {
    T <: Union{ActiveOutPowerVariable, ActivePowerDischargeVariable},
    U <: AbstractTechnologyFormulation,
}
    _add_variable_cost_to_objective!(
        container,
        T(),
        technology,
        om_cost,
        PSY.get_discharge_variable_cost(om_cost),
        U(),
        tech_model,
    )
    return
end

# LinearCurve costs for overnight costs and investment decisions
function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    cost::IS.ValueCurve,
    proportional_term::Float64,
    tech_model::String,
) where {T <: InvestmentVariableType}
    amortized_proportional_term, discount_factor, base_year =
        amortize_overnight_term_to_base_year_dollars(
            container,
            technology,
            proportional_term,
        )
    time_mapping = get_time_mapping(container)
    inv_tuples = get_investment_time_stamps(time_mapping)

    for t in get_investment_time_steps(time_mapping)
        inv_date = inv_tuples[t]
        year = Dates.value.(Dates.Year.(inv_date[1]))
        future_to_present_value = discount_factor^(year - base_year)
        npv_proportional_term = amortized_proportional_term * future_to_present_value
        _add_linearcurve_variable_term_to_model!(
            container,
            T(),
            CapitalCost(),
            technology,
            npv_proportional_term,
            t,
            tech_model,
        )
    end
    return
end

# LinearCurve costs for fixed annual costs. The annual payments on the cumulative capacity of
# each investment period are converted to a lump sum at the start of the period and then
# discounted to the base year.
function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    proportional_term::Float64,
    tech_model::String,
) where {T <: CumulativeInvestmentExpressionType}
    time_mapping = get_time_mapping(container)
    base_year = get_base_year(container)
    discount_rate = get_discount_rate(container)
    inflation_rate = get_inflation_rate(container)
    tech_base_year = PSIP.get_technology_base_year(PSIP.get_financial_data(technology))

    discount_factor = 1 / (1 + discount_rate)
    dollars_to_base_year = (1.0 + inflation_rate)^(-(tech_base_year - base_year))
    inv_tuples = get_investment_time_stamps(time_mapping)

    for t in get_investment_time_steps(time_mapping)
        inv_tuple = inv_tuples[t]
        year = Dates.value.(Dates.Year.(inv_tuple[1]))
        future_to_present_value = discount_factor^(year - base_year)
        period_payments =
            proportional_term * investment_period_annuity_factor(discount_rate, inv_tuple)
        npv_proportional_term =
            period_payments * dollars_to_base_year * future_to_present_value

        _add_linearcurve_variable_term_to_model!(
            container,
            T(),
            FixedOperationModelCost(),
            technology,
            npv_proportional_term,
            t,
            tech_model,
        )
    end
    return
end

# Committed capacity consumes the no-load fuel of its fuel curve
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {T <: CommittedCapacityVariable, U <: AbstractTechnologyFormulation}
    _add_commitment_fuel_cost_to_objective!(
        container,
        T(),
        technology,
        om_cost,
        PSY.get_variable(om_cost),
        U(),
        tech_model,
    )
    return
end

# Capacity that starts up has a start-up cost and consumes the start-up fuel of its fuel curve
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {T <: StartUpCapacityVariable, U <: AbstractTechnologyFormulation}
    _add_start_up_cost_to_objective!(
        container,
        T(),
        technology,
        om_cost,
        PSY.get_start_up(om_cost),
        U(),
        tech_model,
    )
    _add_commitment_fuel_cost_to_objective!(
        container,
        T(),
        technology,
        om_cost,
        PSY.get_variable(om_cost),
        U(),
        tech_model,
    )
    return
end

# Capacity that shuts down has a shut-down cost
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {T <: ShutDownCapacityVariable, U <: AbstractTechnologyFormulation}
    shut_down_cost = PSY.get_shut_down(om_cost)
    if !iszero(shut_down_cost)
        _add_linearcurve_cost!(
            container,
            T(),
            ShutDownCost(),
            technology,
            om_cost,
            objective_function_multiplier(T(), U()) * shut_down_cost,
            tech_model,
        )
    end
    return
end

function _add_start_up_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    start_up_cost::Float64,
    ::U,
    tech_model::String,
) where {T <: StartUpCapacityVariable, U <: AbstractTechnologyFormulation}
    if !iszero(start_up_cost)
        _add_linearcurve_cost!(
            container,
            T(),
            StartUpCost(),
            technology,
            om_cost,
            objective_function_multiplier(T(), U()) * start_up_cost,
            tech_model,
        )
    end
    return
end

function _add_start_up_cost_to_objective!(
    ::SingleOptimizationContainer,
    ::StartUpCapacityVariable,
    technology::PSIP.Technology,
    ::PSY.OperationalCost,
    ::PSY.StartUpStages,
    ::AbstractTechnologyFormulation,
    ::String,
)
    error(
        "Technology $(PSIP.get_name(technology)) defines its start-up cost by stages (hot, " *
        "warm, cold), which is not currently supported. Use a single start-up cost.",
    )
    return
end

function _add_commitment_fuel_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    fuel_curve::PSY.FuelCurve{PSY.LinearCurve},
    ::U,
    tech_model::String,
) where {T <: OperationsVariableType, U <: AbstractTechnologyFormulation}
    fuel_term = get_commitment_fuel(T(), fuel_curve) * get_fuel_price(fuel_curve)
    if !iszero(fuel_term)
        _add_linearcurve_cost!(
            container,
            T(),
            FuelCost(),
            technology,
            om_cost,
            objective_function_multiplier(T(), U()) * fuel_term,
            tech_model,
        )
    end
    return
end

function _add_commitment_fuel_cost_to_objective!(
    ::SingleOptimizationContainer,
    ::OperationsVariableType,
    ::PSIP.Technology,
    ::PSY.OperationalCost,
    ::PSY.CostCurve{PSY.LinearCurve},
    ::AbstractTechnologyFormulation,
    ::String,
)
    return
end

# Costs per hour are weighted by the hours of the year a time step stands for. Start-up and
# shut-down costs are per event, so they are weighted by the occurrences of the period.
get_cost_weight(
    container::SingleOptimizationContainer,
    ::OperationsVariableType,
    op_ix::Int,
) = get_time_step_weight(container, op_ix)
get_cost_weight(
    container::SingleOptimizationContainer,
    ::Union{StartUpCapacityVariable, ShutDownCapacityVariable},
    op_ix::Int,
) = get_operational_weights(container)[op_ix]

# Dispatch for scalar proportional terms
function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    proportional_term::Float64,
    tech_model::String,
) where {T <: OperationsVariableType}
    _add_linearcurve_cost!(
        container,
        T(),
        VariableOMCost(),
        technology,
        om_cost,
        proportional_term,
        tech_model,
    )
    return
end

function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    ::S,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    proportional_term::Float64,
    tech_model::String,
) where {T <: OperationsVariableType, S <: OperationsExpressionType}
    financials = PSIP.get_financial_data(technology)
    base_year = get_base_year(container)
    discount_rate = get_discount_rate(container)
    inflation_rate = get_inflation_rate(container)
    tech_base_year = PSIP.get_technology_base_year(financials)
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    investment_time_stamps = get_investment_time_stamps(time_mapping)

    discount_factor = 1.0 / (1.0 + discount_rate)
    dollars_to_base_year = (1.0 + inflation_rate)^(-(tech_base_year - base_year))
    years = Dates.value.(Dates.Year.(get_time_stamps(time_mapping)))

    for op_ix in get_operational_indexes(time_mapping)
        weight = get_cost_weight(container, T(), op_ix)
        stage = inverse_invest_mapping[op_ix]
        inv_tuple = investment_time_stamps[stage]
        period_factor = investment_period_annuity_factor(discount_rate, inv_tuple)
        for t in consecutive_slices[op_ix]
            future_to_present_value = discount_factor^(years[t] - base_year)
            npv_proportional_term =
                proportional_term * dollars_to_base_year * future_to_present_value
            _add_linearcurve_variable_term_to_model!(
                container,
                T(),
                S(),
                technology,
                period_factor * weight * npv_proportional_term,
                t,
                tech_model,
            )
        end
    end
    return
end

# Add proportional terms to objective function and expression
function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    ::S,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: OperationsVariableType, S <: OperationsExpressionType}
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term,
        time_period,
        tech_model,
    )
    add_to_expression!(container, S, linear_cost, technology, time_period, tech_model)
    return
end

# Add proportional terms to objective function and expression
function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    ::FixedOperationModelCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: CumulativeInvestmentExpressionType}
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term,
        time_period,
        tech_model,
    )
    add_to_expression!(
        container,
        FixedOperationModelCost,
        linear_cost,
        technology,
        time_period,
        tech_model,
    )
    return
end

# Add proportional terms to objective function and expression
function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    ::CapitalCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: BuildInvestmentVariableType}
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term,
        time_period,
        tech_model,
    )
    add_to_expression!(
        container,
        CapitalCost,
        linear_cost,
        technology,
        time_period,
        tech_model,
    )
    return
end

function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    ::CapitalCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: CumulativeCapacity}
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term,
        time_period,
        tech_model,
    )
    add_to_expression!(
        container,
        CapitalCost,
        linear_cost,
        technology,
        time_period,
        tech_model,
    )
    return
end

function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    ::CapitalCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: BuildEnergyCapacity}
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term,
        time_period,
        tech_model,
    )
    add_to_expression!(
        container,
        CapitalCost,
        linear_cost,
        technology,
        time_period,
        tech_model,
    )
    return
end

function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    ::CapitalCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: BuildPowerCapacity}
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term,
        time_period,
        tech_model,
    )
    add_to_expression!(
        container,
        CapitalCost,
        linear_cost,
        technology,
        time_period,
        tech_model,
    )
    return
end

function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    ::CapitalCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: CumulativePowerCapacity}
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term,
        time_period,
        tech_model,
    )
    add_to_expression!(
        container,
        CapitalCost,
        linear_cost,
        technology,
        time_period,
        tech_model,
    )
    return
end

function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    ::CapitalCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: CumulativeEnergyCapacity}
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term,
        time_period,
        tech_model,
    )
    add_to_expression!(
        container,
        CapitalCost,
        linear_cost,
        technology,
        time_period,
        tech_model,
    )
    return
end
