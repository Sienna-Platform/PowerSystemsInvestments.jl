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
    T <:
    Union{PSIP.SupplyTechnology, PSIP.TransmissionTechnology, PSIP.DemandSideTechnology},
    U <: BuildCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        capital_costs = PSIP.get_capital_costs(d)
        value_curve = PSIP.get_capital_cost(capital_costs)
        interconnection_cost = PSIP.get_interconnection_cost(capital_costs)
        _add_cost_to_objective!(
            container,
            U(),
            d,
            value_curve,
            V(),
            tech_model;
            interconnection_cost=interconnection_cost,
        )
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
    variable = get_variable(container, T(), U, tech_model)
    lin_cost = JuMP.AffExpr(0.0)
    for name in get_variable_names(technology)
        JuMP.add_to_expression!(lin_cost, linear_term, variable[name, time_period])
    end
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
    T <: Union{PSIP.SupplyTechnology, PSIP.DemandSideTechnology},
    U <: CumulativeCapacity,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        fixed_cost_data = PSIP.get_operation_costs(d)
        _add_cost_to_objective!(container, U(), d, fixed_cost_data, V(), tech_model)
    end
    return
end

# Storage fixed OM is charged on power capacity only.
function add_fixed_om_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.StorageTechnology,
    U <: CumulativePowerCapacity,
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
    expr = get_expression(container, T(), U, tech_model)
    lin_cost = JuMP.AffExpr(0.0)
    for name in get_variable_names(technology)
        JuMP.add_to_expression!(lin_cost, linear_term, expr[name, time_period])
    end
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
        storage_capital_costs = PSIP.get_capital_costs_storage(d)
        value_curve = PSIP.get_energy_capital_cost(storage_capital_costs)
        _add_cost_to_objective!(container, U(), d, value_curve, V(), tech_model)
    end
    return
end

#######################################
####### BuildPowerCapacity Cost #######
#######################################

# Storage power capacity is symmetric and priced with the discharge capital cost
function get_power_capital_cost(
    technology::PSIP.Technology,
    capital_costs::PSIP.StorageCapitalCost,
)
    if PSIP.get_charge_capital_cost(capital_costs) != PSY.LinearCurve(0.0)
        error(
            "Technology $(PSIP.get_name(technology)) has a charge capital cost, which is " *
            "not supported: storage power capacity is priced with the discharge capital cost.",
        )
    end
    return PSIP.get_discharge_capital_cost(capital_costs)
end

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
        storage_capital_costs = PSIP.get_capital_costs_storage(d)
        value_curve = get_power_capital_cost(d, storage_capital_costs)
        interconnection_cost = PSIP.get_interconnection_cost(storage_capital_costs)
        _add_cost_to_objective!(
            container,
            U(),
            d,
            value_curve,
            V(),
            tech_model;
            interconnection_cost=interconnection_cost,
        )
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
        value_curve, interconnection_cost = get_capital_cost_data(d, U())
        _add_cost_to_objective!(
            container,
            U(),
            d,
            value_curve,
            V(),
            tech_model;
            interconnection_cost=interconnection_cost,
        )
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
    U <: CumulativeInvestmentExpressionType,
    V <: InvestmentTechnologyFormulation,
}
    for d in devices
        fixed_cost_data = get_operation_cost_data(d, U())
        _add_cost_to_objective!(container, U(), d, fixed_cost_data, V(), tech_model)
    end
    return
end
