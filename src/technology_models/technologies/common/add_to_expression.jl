"""
Default implementation to add technology cost variables to VariableOMCost
"""
#add_to_expression!(
#    container,
#    VariableOMCost,
#    linear_cost,
#    component,
#    time_period,
#)
function add_to_expression!(
    container::SingleOptimizationContainer,
    ::Type{S},
    cost_expression::JuMP.AbstractJuMPScalar,
    technology::T,
    time_period::Int,
) where {S <: OperationsExpressionType, T <: PSIP.SupplyTechnology}
    if has_container_key(container, S, T)
        device_cost_expression = get_expression(container, S(), T)
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
) where {S <: InvestmentExpressionType, T <: PSIP.SupplyTechnology}
    if has_container_key(container, S, T)
        device_cost_expression = get_expression(container, S(), T)
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
) where {T <: ActivePowerBalance, U <: OperationsVariableType, V <: PSIP.Technology}
    variable = get_variable(container, U(), V)
    expression = get_expression(container, T(), PSIP.Portfolio)
    multiplier = get_variable_multiplier(U(), V)
    for d in devices, t in get_time_steps(container)
        name = PSY.get_name(d)
        _add_to_jump_expression!(expression[t], variable[name, t], multiplier)
    end
end

#=
function add_to_expression!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    devices::IS.FlattenIteratorWrapper{V},
    #::DeviceModel{V, W},
    #network_model::NetworkModel{X},
) where {
    T <: SupplyTotal,
    U <: ActivePowerVariable,
    V <: PSIP.SupplyTechnology,
    #W <: AbstractTechnologyFormulation,
    #X <: PM.AbstractPowerModel,
}
    variable = get_variable(container, U(), V)
    expression = get_expression(container, T())
    #radial_network_reduction = get_radial_network_reduction(network_model)
    for d in devices, t in get_time_steps(container)
        name = PSY.get_name(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[t],
            variable[name, t],
            1.0 #get_variable_multiplier(U(), V, W()),
        )
    end
    return
end
=#
