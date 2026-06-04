##################################
####### BuildCapacity Cost #######
##################################

function add_capital_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.SupplyTechnology,
    U <: BuildCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        capital_cost_data = PSIP.get_capital_costs(d)
        _add_cost_to_objective!(container, U(), d, capital_cost_data, V(), tech_model)
    end
    return
end

function add_capital_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.AggregateTransportTechnology,
    U <: BuildCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        capital_cost_data = PSIP.get_capital_costs(d)
        _add_cost_to_objective!(container, U(), d, capital_cost_data, V(), tech_model)
    end
    return
end

function add_capital_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.NodalACTransportTechnology,
    U <: BuildCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        capital_cost_data = PSIP.get_capital_costs(d)
        _add_cost_to_objective!(container, U(), d, capital_cost_data, V(), tech_model)
    end
    return
end

function _add_proportional_term!(
    container::SingleOptimizationContainer,
    ::T,
    technology::U,
    linear_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: InvestmentVariableType, U <: PSIP.Technology}
    technology_name = PSIP.get_name(technology)
    #@debug "Linear Variable Cost" _group = LOG_GROUP_COST_FUNCTIONS component_name
    variable = get_variable(container, T(), U, tech_model)[technology_name, time_period]
    lin_cost = variable * linear_term
    add_to_objective_investment_expression!(container, lin_cost)
    return lin_cost
end

#############################
####### Fixed OM Cost #######
#############################

function add_fixed_om_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.SupplyTechnology,
    U <: BuildCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        fixed_cost_data = PSIP.get_operation_costs(d)
        _add_cost_to_objective!(container, U(), d, fixed_cost_data, V(), tech_model)
    end
    return
end

function add_fixed_om_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.StorageTechnology,
    U <: BuildEnergyCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        fixed_cost_data = PSIP.get_operation_costs(d)
        _add_cost_to_objective!(container, U(), d, fixed_cost_data, V(), tech_model)
    end
    return
end

function add_fixed_om_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.StorageTechnology,
    U <: BuildPowerCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        fixed_cost_data = PSIP.get_operation_costs(d)
        _add_cost_to_objective!(container, U(), d, fixed_cost_data, V(), tech_model)
    end
    return
end

function _add_proportional_term!(
    container::SingleOptimizationContainer,
    ::T,
    technology::U,
    linear_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: InvestmentExpressionType, U <: PSIP.Technology}
    technology_name = PSIP.get_name(technology)
    #@debug "Linear Variable Cost" _group = LOG_GROUP_COST_FUNCTIONS component_name
    expr = get_expression(container, T(), U, tech_model)[technology_name, time_period]
    lin_cost = expr * linear_term
    add_to_objective_investment_expression!(container, lin_cost)
    return lin_cost
end

########################################
####### BuildEnergyCapacity Cost #######
########################################

function add_capital_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.StorageTechnology,
    U <: BuildEnergyCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        capital_cost_data = PSIP.get_capital_costs_energy(d)
        _add_cost_to_objective!(container, U(), d, capital_cost_data, V(), tech_model)
    end
    return
end

#######################################
####### BuildPowerCapacity Cost #######
#######################################

function add_capital_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.StorageTechnology,
    U <: BuildPowerCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        capital_cost_data = PSIP.get_capital_costs_discharge(d)
        _add_cost_to_objective!(container, U(), d, capital_cost_data, V(), tech_model)
    end
    return
end

########################################
############ Colocated Costs ###########
########################################

function add_capital_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.ColocatedSupplyStorageTechnology,
    U <: BuildInvestmentVariableType,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        capital_cost_data = get_capital_cost_data(d, U())
        _add_cost_to_objective!(container, U(), d, capital_cost_data, V(), tech_model)
    end
    return
end

function add_fixed_om_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.ColocatedSupplyStorageTechnology,
    U <: BuildInvestmentVariableType,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        fixed_cost_data = get_operation_cost_data(d, U())
        _add_cost_to_objective!(container, U(), d, fixed_cost_data, V(), tech_model)
    end
    return
end
