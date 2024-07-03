mutable struct InvestmentModel{I <: InvestmentProblem, S <: SolutionAlgorithm}
    portfolio::PSIP.Portfolio
    internal::Union{Nothing, ISOPT.ModelInternal}
    store::InvestmentModelStore
    ext::Dict{String, Any}
end
