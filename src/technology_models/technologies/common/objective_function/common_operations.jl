##################################
#### ActivePowerVariable Cost ####
##################################

function add_variable_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ::V,
    tech_model::String,
) where {T <: PSIP.SupplyTechnology, U <: ActivePowerVariable, V <: BasicDispatch}
    for d in devices
        op_cost_data = PSIP.get_operation_costs(d)
        _add_cost_to_objective!(container, U(), d, op_cost_data, V(), tech_model)
    end
    return
end

#=
function add_proportional_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ::V,
) where {T <: PSY.ThermalGen, U <: OnVariable, V <: AbstractCompactUnitCommitment}
    multiplier = objective_function_multiplier(U(), V())
    for d in devices
        op_cost_data = PSY.get_operation_cost(d)
        cost_term = proportional_cost(op_cost_data, U(), d, V())
        iszero(cost_term) && continue
        for t in get_time_steps(time_mapping)
            exp = _add_proportional_term!(container, U(), d, cost_term * multiplier, t)
            add_to_expression!(container, ProductionCostExpression, exp, d, t)
        end
    end
    return
end
=#

function _add_proportional_term!(
    container::SingleOptimizationContainer,
    ::T,
    technology::U,
    linear_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: ActivePowerVariable, U <: PSIP.Technology}
    technology_name = PSIP.get_name(technology)
    #@debug "Linear Variable Cost" _group = LOG_GROUP_COST_FUNCTIONS component_name
    variable = get_variable(container, T(), U, tech_model)[technology_name, time_period]
    lin_cost = variable * linear_term
    add_to_objective_operations_expression!(container, lin_cost)
    return lin_cost
end

#=
function _add_variable_cost_to_objective!(
    container::SingleOptimizationContainer,
    ::T,
    technology::PSIP.Technology,
    op_cost::PSY.ValueCurve,
    ::U,
) where {T <: VariableType, U <: AbstractTechnologyFormulation}
    # Using value curves for now, so this is not needed (but might be later?)
    #variable_cost_data = variable_cost(op_cost, T(), component, U())
    _add_variable_cost_to_objective!(container, T(), component, variable_cost_data, U())
    return
end
=#

##################################
#### ActiveIn/OutPowerVariable Cost ####
##################################
function _add_proportional_term!(
    container::SingleOptimizationContainer,
    ::T,
    technology::U,
    linear_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: ActiveInPowerVariable, U <: PSIP.Technology}
    technology_name = PSIP.get_name(technology)
    #@debug "Linear Variable Cost" _group = LOG_GROUP_COST_FUNCTIONS component_name
    variable = get_variable(container, T(), U, tech_model)[technology_name, time_period]
    lin_cost = variable * linear_term
    add_to_objective_operations_expression!(container, lin_cost)
    return lin_cost
end

function _add_proportional_term!(
    container::SingleOptimizationContainer,
    ::T,
    technology::U,
    linear_term::Float64,
    time_period::Int,
    tech_model::String,
) where {T <: ActiveOutPowerVariable, U <: PSIP.Technology}
    technology_name = PSIP.get_name(technology)
    #@debug "Linear Variable Cost" _group = LOG_GROUP_COST_FUNCTIONS component_name
    variable = get_variable(container, T(), U, tech_model)[technology_name, time_period]
    lin_cost = variable * linear_term
    add_to_objective_operations_expression!(container, lin_cost)
    return lin_cost
end

function add_variable_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    ::V,
    tech_model::String,
) where {
    T <: PSIP.StorageTechnology,
    U <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    V <: BasicDispatch,
}
    for d in devices
        op_cost_data = PSIP.get_operations_costs_power(d)
        _add_cost_to_objective!(container, U(), d, op_cost_data, V(), tech_model)
    end
    return
end
