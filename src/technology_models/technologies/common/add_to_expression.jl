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
