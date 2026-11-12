abstract type AbstractInvestmentProblem <: IOM.AbstractOptimizationProblem end

# Implementation of the build and solve algorithm is done in the respective folders.
struct SingleInstanceSolve <: AbstractInvestmentProblem end
