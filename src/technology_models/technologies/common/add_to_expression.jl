function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: Union{VariableOMCost, StartUpCost, ShutDownCost},
    U <: Vector{D},
    V <: OperationsTechnologyFormulation,
} where {D <: PSIP.Technology}
    IS.@assert_op length(devices) > 0
    add_expression_container!(
        container,
        expression_type,
        D,
        get_variable_names(devices),
        get_time_steps(get_time_mapping(container)),
        meta=string(V),
    )
    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: Union{CapitalCostExpression, FixedOperationModelCost},
    U <: Vector{D},
    V <: InvestmentTechnologyFormulation,
} where {D <: PSIP.Technology}
    IS.@assert_op length(devices) > 0
    add_expression_container!(
        container,
        expression_type,
        D,
        get_variable_names(devices),
        get_investment_time_steps(get_time_mapping(container)),
        meta=string(V),
    )
    return
end

# Only formulations that create the cost expression report to it
function add_to_expression!(
    container::SingleOptimizationContainer,
    ::Type{S},
    cost_expression::JuMP.AbstractJuMPScalar,
    technology::T,
    name::String,
    time_period::Int,
    tech_model::String,
) where {S <: ExpressionType, T <: PSIP.Technology}
    if has_container_key(container, S, T, tech_model)
        device_cost_expression = get_expression(container, S(), T, tech_model)
        JuMP.add_to_expression!(device_cost_expression[name, time_period], cost_expression)
    end
    return
end
