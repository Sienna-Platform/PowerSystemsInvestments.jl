abstract type SolutionAlgorithm end

# Implementation of the build and solve algorithm is done in the respective folders.
struct SingleInstanceSolve <: SolutionAlgorithm end

"""
Solves a `NodalPTDFModel` model monitoring only the corridors that need it: after each solve,
the corridors whose exact flow exceeds their limit are added, until none does. The first solve
monitors the `"monitored"` corridors (none by default). Corridors can be left overloaded when
`"max_iterations"` is reached, or by the `"relative_tol"` of the transport model; both cases
log a warning and make [`get_monitoring_converged`](@ref) return `false`.

Transport model attributes: `"max_iterations"` (default 20) and `"overload_tolerance"` (share
above the limit, default 1e-4). For a MIP, `"relaxed_screening"` (default `true`) first
iterates with integrality relaxed, and `"screening_mip_gap"` (default none) iterates with a
looser gap before a final solve with the solver's gap.
"""
struct IterativeMonitoring <: SolutionAlgorithm end
