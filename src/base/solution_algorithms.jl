abstract type SolutionAlgorithm end

# Implementation of the build and solve algorithm is done in the respective folders.
struct SingleInstanceSolve <: SolutionAlgorithm end

"""
Solves a model with the `NodalPTDFModel` transport model, limiting only the corridors whose flow
needs it. The first solve limits the corridors listed in the `"monitored"` attribute (none when it
is not set). After each solve, the unmonitored corridors whose exact flow exceeds their limit start
being monitored, and the model is solved again, until no unmonitored corridor is overloaded.
Corridors are added to the built model, so each solve starts from the previous one.

Transport model attributes:

  - `"max_iterations"`: largest number of solves after the first (default 20);
  - `"overload_tolerance"`: share above its limit at which a corridor counts as overloaded
    (default 1e-4);
  - `"add_threshold"`: loading above which unmonitored corridors are added once some are
    overloaded (default 1.0, only the overloaded ones).

With a PTDF cutoff (`"tol"`), monitored corridors can end slightly above their limits in the exact
flows; they are reported, not corrected. See [`get_monitoring_log`](@ref).
"""
struct IterativeMonitoring <: SolutionAlgorithm end
