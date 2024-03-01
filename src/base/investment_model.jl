mutable struct InvestmentModel{<: InvestmentProblem}
    portfolio::PSIP.Portfolio
    container::OptimizationContainer
end
