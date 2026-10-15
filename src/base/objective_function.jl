# PSI uses IOM.ObjectiveFunction directly.
# PSI's public API keeps explicit capital/operation term accessors; maintain a sidecar map for
# those terms while IOM stores solver-facing invariant/variant expressions.

mutable struct _PSIObjectiveTerms
    capital_terms
    operation_terms
end

const _OBJECTIVE_TERMS = IdDict{IOM.ObjectiveFunction, _PSIObjectiveTerms}()
const _LAST_OBJECTIVE_FUNCTION = Ref{Union{Nothing, IOM.ObjectiveFunction}}(nothing)

function _register_objective_function!(obj::IOM.ObjectiveFunction)
    _OBJECTIVE_TERMS[obj] = _PSIObjectiveTerms(zero(JuMP.AffExpr), zero(JuMP.AffExpr))
    _LAST_OBJECTIVE_FUNCTION[] = obj
    return
end

function _track_objective_capital_terms!(obj::IOM.ObjectiveFunction, expr)
    terms = get!(_OBJECTIVE_TERMS, obj, _PSIObjectiveTerms(zero(JuMP.AffExpr), zero(JuMP.AffExpr)))
    terms.capital_terms = terms.capital_terms + expr
    return
end

function _track_objective_operation_terms!(obj::IOM.ObjectiveFunction, expr)
    terms = get!(_OBJECTIVE_TERMS, obj, _PSIObjectiveTerms(zero(JuMP.AffExpr), zero(JuMP.AffExpr)))
    terms.operation_terms = terms.operation_terms + expr
    return
end

function ObjectiveFunction()
    obj = _LAST_OBJECTIVE_FUNCTION[]
    return isnothing(obj) ? IOM.ObjectiveFunction() : obj
end

function get_capital_terms(v::IOM.ObjectiveFunction)
    return get(_OBJECTIVE_TERMS, v, _PSIObjectiveTerms(IOM.get_invariant_terms(v), IOM.get_variant_terms(v))).capital_terms
end

function get_operation_terms(v::IOM.ObjectiveFunction)
    return get(_OBJECTIVE_TERMS, v, _PSIObjectiveTerms(IOM.get_invariant_terms(v), IOM.get_variant_terms(v))).operation_terms
end

get_sense(v::IOM.ObjectiveFunction) = IOM.get_sense(v)
set_sense!(v::IOM.ObjectiveFunction, sense::MOI.OptimizationSense) = IOM.set_sense!(v, sense)
