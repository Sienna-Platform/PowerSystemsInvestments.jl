mutable struct ObjectiveFunction
    expression::JuMP.AbstractJuMPScalar
    capital_terms::JuMP.AbstractJuMPScalar
    operation_terms::JuMP.AbstractJuMPScalar
    sense::MOI.OptimizationSense
    function ObjectiveFunction(
        capital_terms::JuMP.AbstractJuMPScalar,
        operation_terms::JuMP.AbstractJuMPScalar,
        sense::MOI.OptimizationSense = MOI.MIN_SENSE)
        new(capital_terms, operation_terms, sense)
    end
end

get_capital_terms(v::ObjectiveFunction) = v.capital_terms
get_operation_terms(v::ObjectiveFunction) = v.operation_terms

function get_objective_expression(v::ObjectiveFunction)
    return JuMP.add_to_expression!(v.capital_terms, v.operation_terms)
end
get_sense(v::ObjectiveFunction) = v.sense

set_sense!(v::ObjectiveFunction, sense::MOI.OptimizationSense) = v.sense = sense

function ObjectiveFunction()
    return ObjectiveFunction(
        zero(JuMP.GenericAffExpr{Float64, JuMP.VariableRef}),
        zero(JuMP.AffExpr),
        true,
    )
end

mutable struct OptimizationContainer <: IS.AbstractOptimizationContainer
    JuMPmodel::JuMP.Model
    time_steps::UnitRange{Int}
    resolution::Dates.TimePeriod
    settings::Settings
    settings_copy::Settings
    variables::Dict{IS.VariableKey, AbstractArray}
    aux_variables::Dict{AuxVarKey, AbstractArray}
    duals::Dict{IS.ConstraintKey, AbstractArray}
    constraints::Dict{IS.ConstraintKey, AbstractArray}
    objective_function::ObjectiveFunction
    expressions::Dict{IS.ExpressionKey, AbstractArray}
    parameters::Dict{IS.ParameterKey, ParameterContainer}
    infeasibility_conflict::Dict{Symbol, Array}
    optimizer_stats::IS.OptimizerStats
    metadata::IS.OptimizationContainerMetadata
end
