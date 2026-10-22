abstract type SolutionAlgorithm end

# Implementation of the build and solve algorithm is done in the respective folders.
struct SingleInstanceSolve <: SolutionAlgorithm end

"""
Solves a model with the `NodalPTDFModel` transport model, monitoring only the corridors that
need it: after each solve, the corridors whose exact flow exceeds their limit are added and the
model is solved again, until none is overloaded. The first solve monitors the `"monitored"`
corridors (none by default).

Transport model attributes: `"max_iterations"` (default 20), `"overload_tolerance"` (share above
the limit, default 1e-4) and `"add_threshold"` (once some corridors are overloaded, also add
those loaded above this share; default 1.0).
"""
struct IterativeMonitoring <: SolutionAlgorithm end
