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
    tech_model::String,
) where {T <: VariableType, U <: AbstractTechnologyFormulation}
    cost_component = PSY.get_function_data(value_curve)
    proportional_term = PSY.get_proportional_term(cost_component)
    @debug "Cost is assumed to be in natural units: \$/MWh"
    # TODO: multiplier
    multiplier = 1.0 #objective_function_multiplier(T(), U())
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

#TODO: Organize these functions and move them to technology-specific files
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    value_curve::IS.ValueCurve,
    ::U,
    tech_model::String,
) where {T <: VariableType, U <: IntegerInvestment}
    cost_component = PSY.get_function_data(value_curve)
    proportional_term = PSY.get_proportional_term(cost_component)
    @debug "Cost is assumed to be in natural units: \$/MWh"
    # TODO: multiplier
    multiplier = PSIP.get_unit_size(technology) #objective_function_multiplier(T(), U())
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

#TODO: Organize these functions and move them to technology-specific files
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    value_curve::IS.ValueCurve,
    ::U,
    tech_model::String,
) where {T <: BuildEnergyCapacity, U <: IntegerInvestment}
    cost_component = PSY.get_function_data(value_curve)
    proportional_term = PSY.get_proportional_term(cost_component)
    @debug "Cost is assumed to be in natural units: \$/MWh"
    multiplier = PSIP.get_unit_size_energy(technology) #objective_function_multiplier(T(), U())
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

function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    value_curve::IS.ValueCurve,
    ::U,
    tech_model::String,
) where {T <: BuildPowerCapacity, U <: IntegerInvestment}
    cost_component = PSY.get_function_data(value_curve)
    proportional_term = PSY.get_proportional_term(cost_component)
    @debug "Cost is assumed to be in natural units: \$/MWh"
    multiplier = PSIP.get_unit_size_power(technology) 
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

#Fixed OM calculated from build capacity
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {T <: BuildCapacity, U <: AbstractTechnologyFormulation}
    proportional_term = PSY.get_fixed(om_cost)
    multiplier = 1.0
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

function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.StorageCost,
    ::U,
    tech_model::String,
) where {T <: InvestmentVariableType, U <: AbstractTechnologyFormulation}
    proportional_term = PSY.get_fixed(om_cost)
    multiplier = 1.0
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
) where {T <: ActivePowerVariable, U <: AbstractTechnologyFormulation}
    cost_curve = PSY.get_variable(om_cost)
    value_curve = PSY.get_value_curve(cost_curve)
    proportional_term = PSY.get_proportional_term(value_curve)
    multiplier = 1.0 #objective_function_multiplier(T(), U())
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

#Storage Charge cost
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {T <: ActiveInPowerVariable, U <: AbstractTechnologyFormulation}
    cost_curve = PSY.get_charge_variable_cost(om_cost)
    value_curve = PSY.get_value_curve(cost_curve)
    proportional_term = PSY.get_proportional_term(value_curve)
    multiplier = 1.0 #objective_function_multiplier(T(), U())
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

#Storage Discharge cost
function _add_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    ::U,
    tech_model::String,
) where {T <: ActiveOutPowerVariable, U <: AbstractTechnologyFormulation}
    cost_curve = PSY.get_discharge_variable_cost(om_cost)
    value_curve = PSY.get_value_curve(cost_curve)
    proportional_term = PSY.get_proportional_term(value_curve)
    multiplier = 1.0 #objective_function_multiplier(T(), U())
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

# LinearCurve costs for overnight costs and investment decisions
function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    cost::IS.ValueCurve,
    proportional_term::Float64,
    tech_model::String,
) where {T <: InvestmentVariableType}
    time_mapping = get_time_mapping(container)
    base_year = get_base_year(container)
    discount_rate = get_discount_rate(container)
    inflation_rate = get_inflation_rate(container)
    interest_rate = PSIP.get_interest_rate(technology)
    tech_base_year = PSIP.get_base_year(technology)
    capital_recovery_period = PSIP.get_capital_recovery_period(technology)

    capital_recovery_factor =
        interest_rate / (1 - (1 + interest_rate)^(-(capital_recovery_period)))
    lump_amortized_payments =
        (1 - (1 + discount_rate)^(-(capital_recovery_period))) / discount_rate
    discount_factor = 1 / (1 + discount_rate)
    dollars_to_base_year = (1.0 + inflation_rate)^(-(tech_base_year - base_year))
    inv_tuples = get_investment_time_stamps(time_mapping)

    for t in get_investment_time_steps(time_mapping)
        inv_date = inv_tuples[t]
        year = Dates.value.(Dates.Year.(inv_date[1]))
        future_to_present_value = discount_factor^(year - base_year)
        npv_proportional_term =
            proportional_term *
            capital_recovery_factor *
            lump_amortized_payments *
            dollars_to_base_year *
            future_to_present_value
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

# LinearCurve costs for fixed annual costs
function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    proportional_term::Float64,
    tech_model::String,
) where {T <: InvestmentVariableType}
    time_mapping = get_time_mapping(container)
    base_year = get_base_year(container)
    discount_rate = get_discount_rate(container)
    inflation_rate = get_inflation_rate(container)
    interest_rate = PSIP.get_interest_rate(technology)
    tech_base_year = PSIP.get_base_year(technology)
    lifetime = PSIP.get_lifetime(technology)
    lump_annual_payments = (1 - (1 + discount_rate)^(-(lifetime))) / discount_rate
    discount_factor = 1 / (1 + discount_rate)
    dollars_to_base_year = (1.0 + inflation_rate)^(-(tech_base_year - base_year))
    inv_tuples = get_investment_time_stamps(time_mapping)

    for t in get_investment_time_steps(time_mapping)
        inv_date = inv_tuples[t]
        year = Dates.value.(Dates.Year.(inv_date[1]))
        future_to_present_value = discount_factor^(year - base_year)
        npv_proportional_term =
            proportional_term *
            lump_annual_payments *
            dollars_to_base_year *
            future_to_present_value
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

function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    proportional_term::Float64,
    tech_model::String,
) where {T <: InvestmentExpressionType}
    time_mapping = get_time_mapping(container)
    base_year = get_base_year(container)
    discount_rate = get_discount_rate(container)
    inflation_rate = get_inflation_rate(container)
    interest_rate = PSIP.get_interest_rate(technology)
    tech_base_year = PSIP.get_base_year(technology)
    lifetime = PSIP.get_capital_recovery_period(technology)

    discount_factor = 1 / (1 + discount_rate)
    dollars_to_base_year = (1.0 + inflation_rate)^(-(tech_base_year - base_year))
    inv_tuples = get_investment_time_stamps(time_mapping)

    for t in get_investment_time_steps(time_mapping)
        inv_tuple = inv_tuples[t]
        year = Dates.value.(Dates.Year.(inv_tuple[1]))
        future_to_present_value = discount_factor^(year - base_year)
        npv_proportional_term =
            proportional_term * dollars_to_base_year * future_to_present_value

        _add_linearcurve_variable_term_to_model!(
            container,
            T(),
            VariableOMCost(),
            technology,
            npv_proportional_term,
            t,
            tech_model,
        )
    end
    return
end

# Dispatch for scalar proportional terms
function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    om_cost::PSY.OperationalCost,
    proportional_term::Float64,
    tech_model::String,
) where {T <: OperationsVariableType}
    base_year = get_base_year(container)
    discount_rate = get_discount_rate(container)
    inflation_rate = get_inflation_rate(container)
    tech_base_year = PSIP.get_base_year(technology)
    time_mapping = get_time_mapping(container)
    operational_weights = get_operational_weights(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    discount_factor = 1.0 / (1.0 + discount_rate)
    dollars_to_base_year = (1.0 + inflation_rate)^(-(tech_base_year - base_year))
    years = Dates.value.(Dates.Year.(get_time_stamps(time_mapping)))

    for op_ix in get_operational_indexes(time_mapping)
        weight = operational_weights[op_ix]
        for t in consecutive_slices[op_ix]
            future_to_present_value = discount_factor^(years[t] - base_year)
            npv_proportional_term =
                proportional_term * dollars_to_base_year * future_to_present_value
            _add_linearcurve_variable_term_to_model!(
                container,
                T(),
                VariableOMCost(),
                technology,
                weight * npv_proportional_term,
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
    ::VariableOMCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: ActivePowerVariable}
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
        VariableOMCost,
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
    ::VariableOMCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: Union{ActiveInPowerVariable, ActiveOutPowerVariable}}
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
        VariableOMCost,
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
    ::FixedOperationModelCost,
    technology::PSIP.Technology,
    proportional_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: InvestmentVariableType}
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
) where {T <: BuildCapacity}
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
