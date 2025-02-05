"""
Default implementation to add technology cost variables to VariableOMCost
"""
function add_to_expression!(
    container::SingleOptimizationContainer,
    ::Type{S},
    cost_expression::JuMP.AbstractJuMPScalar,
    technology::T,
    time_period::Int,
    tech_model::String,
) where {S <: OperationsExpressionType, T <: PSIP.SupplyTechnology}
    if has_container_key(container, S, T)
        device_cost_expression = get_expression(container, S(), T, tech_model)
        component_name = PSY.get_name(technology)
        JuMP.add_to_expression!(
            device_cost_expression[component_name, time_period],
            cost_expression,
        )
    end
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    ::Type{S},
    cost_expression::JuMP.AbstractJuMPScalar,
    technology::T,
    time_period::Int,
    tech_model::String,
) where {S <: InvestmentExpressionType, T <: PSIP.SupplyTechnology}
    if has_container_key(container, S, T)
        device_cost_expression = get_expression(container, S(), T, tech_model)
        component_name = PSY.get_name(technology)
        JuMP.add_to_expression!(
            device_cost_expression[component_name, time_period],
            cost_expression,
        )
    end
    return
end

### StorageTechnology add_to_expression
function add_to_expression!(
    container::SingleOptimizationContainer,
    ::Type{S},
    cost_expression::JuMP.AbstractJuMPScalar,
    technology::T,
    time_period::Int,
    tech_model::String,
) where {S <: OperationsExpressionType, T <: PSIP.StorageTechnology}
    if has_container_key(container, S, T)
        device_cost_expression = get_expression(container, S(), T, tech_model)
        component_name = PSY.get_name(technology)
        JuMP.add_to_expression!(
            device_cost_expression[component_name, time_period],
            cost_expression,
        )
    end
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    ::Type{S},
    cost_expression::JuMP.AbstractJuMPScalar,
    technology::T,
    time_period::Int,
    tech_model::String,
) where {S <: InvestmentExpressionType, T <: PSIP.StorageTechnology}
    if has_container_key(container, S, T)
        device_cost_expression = get_expression(container, S(), T, tech_model)
        component_name = PSY.get_name(technology)
        JuMP.add_to_expression!(
            device_cost_expression[component_name, time_period],
            cost_expression,
        )
    end
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    ::Type{S},
    cost_expression::JuMP.AbstractJuMPScalar,
    technology::T,
    time_period::Int,
    tech_model::String,
) where {S <: InvestmentExpressionType, T <: GenericTransportTechnology}
    if has_container_key(container, S, T)
        device_cost_expression = get_expression(container, S(), T, tech_model)
        component_name = PSY.get_name(technology)
        JuMP.add_to_expression!(
            device_cost_expression[component_name, time_period],
            cost_expression,
        )
    end
    return
end
"""
Default implementation to add device variables to SystemBalanceExpressions
"""
function add_to_expression!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
) where {T <: EnergyBalance, U <: OperationsVariableType, V <: PSIP.Technology}
    variable = get_variable(container, U(), V)
    expression = get_expression(container, T(), PSIP.Portfolio)
    multiplier = get_variable_multiplier(U(), V)
    for d in devices, t in get_time_steps(time_mapping)
        name = PSY.get_name(d)
        _add_to_jump_expression!(expression[t], variable[name, t], multiplier)
    end
end
