mutable struct ObjectiveFunction
    expression::JuMP.AbstractJuMPScalar
    capital_terms::JuMP.AbstractJuMPScalar
    operation_terms::JuMP.AbstractJuMPScalar
    sense::MOI.OptimizationSense
    function ObjectiveFunction(
        capital_terms::JuMP.AbstractJuMPScalar,
        operation_terms::JuMP.AbstractJuMPScalar,
        sense::MOI.OptimizationSense=MOI.MIN_SENSE,
    )
        new(zero(JuMP.AffExpr), capital_terms, operation_terms, sense)
    end
end

get_capital_terms(v::ObjectiveFunction) = v.capital_terms
get_operation_terms(v::ObjectiveFunction) = v.operation_terms

function get_objective_expression(v::ObjectiveFunction)
    return v.capital_terms + v.operation_terms
end
get_sense(v::ObjectiveFunction) = v.sense

set_sense!(v::ObjectiveFunction, sense::MOI.OptimizationSense) = v.sense = sense

function ObjectiveFunction()
    return ObjectiveFunction(zero(JuMP.AffExpr), zero(JuMP.AffExpr), MOI.MIN_SENSE)
end

function add_to_capital_terms(v::ObjectiveFunction, val::Union{JuMP.AffExpr, Float64})
    JuMP.add_to_expression!(v.capital_terms, val)
    return
end

function add_to_operation_terms(v::ObjectiveFunction, val::Union{JuMP.AffExpr, Float64})
    JuMP.add_to_expression!(v.operation_terms, val)
    return
end

function add_to_capital_terms(v::ObjectiveFunction, val::JuMP.QuadExpr)
    v.capital_terms += val
    return
end

function add_to_operation_terms(v::ObjectiveFunction, val::JuMP.QuadExpr)
    v.operation_terms += val
    return
end
