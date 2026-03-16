# PSI uses IOM.ObjectiveFunction directly.
# PSI's capital_terms map to IOM's invariant_terms.
# PSI's operation_terms map to IOM's variant_terms.

const ObjectiveFunction = IOM.ObjectiveFunction

get_capital_terms(v::IOM.ObjectiveFunction) = IOM.get_invariant_terms(v)
get_operation_terms(v::IOM.ObjectiveFunction) = IOM.get_variant_terms(v)
get_sense(v::IOM.ObjectiveFunction) = IOM.get_sense(v)
set_sense!(v::IOM.ObjectiveFunction, sense::MOI.OptimizationSense) = IOM.set_sense!(v, sense)
