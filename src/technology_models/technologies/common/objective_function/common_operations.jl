#! format: off

objective_function_multiplier(::VariableType, ::AbstractTechnologyFormulation)=OBJECTIVE_FUNCTION_POSITIVE

#! format: on

##################################
#### ActivePowerVariable Cost ####
##################################

function add_variable_cost!(
    container::OptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {T <: PSIP.SupplyTechnology, U <: ActivePowerVariable, V <: BasicDispatch}
    for d in devices
        op_cost_data = PSIP.get_operation_costs(d)
        _add_cost_to_objective!(container, U(), d, op_cost_data, V(), tech_model)
    end
    return
end

function _add_proportional_term!(
    container::OptimizationContainer,
    ::T,
    technology::U,
    linear_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: OperationsVariableType, U <: PSIP.Technology}
    technology_name = PSIP.get_name(technology)
    variable = get_variable(container, T(), U, tech_model)[technology_name, time_period]
    lin_cost = variable * linear_term
    add_to_objective_operations_expression!(container, lin_cost)
    return lin_cost
end

########################################
#### ActiveIn/OutPowerVariable Cost ####
########################################

function add_variable_cost!(
    container::OptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.StorageTechnology,
    U <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    V <: OperationsStorageFormulation,
}
    for d in devices
        op_cost_data = PSIP.get_operation_costs(d)
        _add_cost_to_objective!(container, U(), d, op_cost_data, V(), tech_model)
    end
    return
end

function add_variable_cost!(
    container::OptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.ColocatedSupplyStorageTechnology,
    U <: OperationsVariableType,
    V <: OperationsColocatedFormulation,
}
    for d in devices
        op_cost_data = get_operation_cost_data(d, U())
        _add_cost_to_objective!(container, U(), d, op_cost_data, V(), tech_model)
    end
    return
end
