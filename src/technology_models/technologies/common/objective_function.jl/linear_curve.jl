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
) where {T <: VariableType, U <: AbstractTechnologyFormulation}
    #base_power = get_base_power(component)
    device_base_power = PSIP.get_base_power(technology)
    #value_curve = PSY.get_value_curve(cost_function)
    #power_units = PSY.get_power_units(cost_function)
    cost_component = PSY.get_function_data(value_curve)
    proportional_term = PSY.get_proportional_term(cost_component)
    proportional_term_per_unit = get_proportional_cost_per_system_unit(
        proportional_term,
        #power_units,
        #base_power,
        device_base_power,
    )
    @warn "TODO: multiplier"
    multiplier = 1.0 #objective_function_multiplier(T(), U())
    _add_linearcurve_cost!(
        container,
        T(),
        technology,
        multiplier * proportional_term_per_unit,
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
) where {T <: ExpressionType, U <: AbstractTechnologyFormulation}
    #base_power = get_base_power(component)
    device_base_power = PSIP.get_base_power(technology)
    #value_curve = PSY.get_value_curve(cost_function)
    #power_units = PSY.get_power_units(cost_function)
    #cost_component = PSY.get_function_data(value_curve)
    proportional_term = PSY.get_fixed(om_cost)
    proportional_term_per_unit = get_proportional_cost_per_system_unit(
        proportional_term,
        #power_units,
        #base_power,
        device_base_power,
    )
    multiplier = 1.0 #objective_function_multiplier(T(), U())
    _add_linearcurve_cost!(
        container,
        T(),
        technology,
        multiplier * proportional_term_per_unit,
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
) where {T <: VariableType, U <: AbstractTechnologyFormulation}
    #base_power = get_base_power(component)
    device_base_power = PSIP.get_base_power(technology)

    cost_curve = PSY.get_variable(om_cost)
    value_curve = PSY.get_value_curve(cost_curve)
    proportional_term = PSY.get_proportional_term(value_curve)
    proportional_term_per_unit = get_proportional_cost_per_system_unit(
        proportional_term,
        #power_units,
        #base_power,
        device_base_power,
    )
    multiplier = 1.0 #objective_function_multiplier(T(), U())
    _add_linearcurve_cost!(
        container,
        T(),
        technology,
        multiplier * proportional_term_per_unit,
    )
    return
end

# Following same structure as PowerSimulations, but removing system units for now
function get_proportional_cost_per_system_unit(
    cost_term::Float64,
    #unit_system::PSY.UnitSystem,
    #system_base_power::Float64,
    device_base_power::Float64,
)
    return _get_proportional_cost_per_system_unit(
        cost_term,
        #Val{unit_system}(),
        #system_base_power,
        device_base_power,
    )
end

function _get_proportional_cost_per_system_unit(
    cost_term::Float64,
    #::Val{PSY.UnitSystem.SYSTEM_BASE},
    #system_base_power::Float64,
    device_base_power::Float64,
)
    return cost_term
end

# Dispatch for scalar proportional terms
function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    proportional_term_per_unit::Float64,
) where {T <: InvestmentVariableType}
    for t in get_time_steps_investments(container)
        _add_linearcurve_variable_term_to_model!(
            container,
            T(),
            technology,
            proportional_term_per_unit,
            t,
        )
    end
    return
end

function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    proportional_term_per_unit::Float64,
) where {T <: InvestmentExpressionType}
    for t in get_time_steps_investments(container)
        _add_linearcurve_variable_term_to_model!(
            container,
            T(),
            technology,
            proportional_term_per_unit,
            t,
        )
    end
    return
end

# Dispatch for scalar proportional terms
function _add_linearcurve_cost!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    proportional_term_per_unit::Float64,
) where {T <: OperationsVariableType}
    @warn "Add Scaling to Operational Terms to compare with Capital Terms"
    for t in get_time_steps(container)
        _add_linearcurve_variable_term_to_model!(
            container,
            T(),
            technology,
            proportional_term_per_unit,
            t,
        )
    end
    return
end

# Add proportional terms to objective function and expression
function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    proportional_term_per_unit::Float64,
    time_period::Int,
) where {T <: ActivePowerVariable}
    resolution = get_resolution(container)

    # TODO: Need to add in some way to calculate how to scale/weight these representative days/hours up to the full investment period
    # @warn: Update hard code resolution
    operational_timepoint_scaling = 365
    resolution = Dates.Hour(1)
    dt =
        Dates.value(Dates.Millisecond(resolution)) / MILLISECONDS_IN_HOUR *
        operational_timepoint_scaling
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term_per_unit * dt,
        time_period,
    )
    add_to_expression!(container, VariableOMCost, linear_cost, technology, time_period)
    return
end

# Add proportional terms to objective function and expression
function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    proportional_term_per_unit::Float64,
    time_period::Int,
) where {T <: BuildCapacity}

    # TODO: How are we handling investment vs. operation resolutions?
    #resolution = get_resolution(container)

    dt = 1
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term_per_unit * dt,
        time_period,
    )
    add_to_expression!(container, CapitalCost, linear_cost, technology, time_period)
    return
end

function _add_linearcurve_variable_term_to_model!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    proportional_term_per_unit::Float64,
    time_period::Int,
) where {T <: CumulativeCapacity}

    # TODO: How are we handling investment vs. operation resolutions?
    #resolution = get_resolution(container)

    dt = 1
    linear_cost = _add_proportional_term!(
        container,
        T(),
        technology,
        proportional_term_per_unit * dt,
        time_period,
    )
    add_to_expression!(container, CapitalCost, linear_cost, technology, time_period)
    return
end
