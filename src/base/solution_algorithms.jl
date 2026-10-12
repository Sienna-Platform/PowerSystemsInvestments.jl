"""
Abstract supertype for the algorithms used to build and solve an [`InvestmentModel`](@ref).
"""
abstract type SolutionAlgorithm end

# Implementation of the build and solve algorithm is done in the respective folders.
"""
Solution algorithm that builds the full problem as one optimization model and solves it once.
"""
struct SingleInstanceSolve <: SolutionAlgorithm end
