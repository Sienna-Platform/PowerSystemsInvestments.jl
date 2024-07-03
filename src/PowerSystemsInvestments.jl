module PowerSystemsInvestments

import InfrastructureSystems
import PowerSystems
import JuMP
import MathOptInterface
import PowerSystemsInvestmentsPortfolios

const IS = InfrastructureSystems
const ISOPT = InfrastructureSystems.Optimization
const PSY = PowerSystems
const MOI = MathOptInterface
const PSIP = PowerSystemsInvestmentsPortfolios

export InvestmentModel
export SimpleCapacityExpansion

using DocStringExtensions

include("base/constraints.jl")
include("base/variables.jl")
include("base/expressions.jl")
include("base/solution_algorithms.jl")
include("base/optimization_container.jl")
include("base/capital_model.jl")
include("base/operation_model.jl")
include("base/feasibility_model.jl")
include("base/investment_problem.jl")
include("base/investment_model_store.jl")
include("base/investment_model.jl")

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

end
