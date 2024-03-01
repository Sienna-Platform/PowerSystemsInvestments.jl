mutable struct InvestmentModel{<: InvestmentProblem}
    portfolio::PSIP.Portfolio
    internal::Union{Nothing, IS.ModelInternal}
    store::InvestmentModelStore
    ext::Dict{String, Any}
end
