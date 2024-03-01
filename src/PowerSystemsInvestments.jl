module PowerSystemsInvestments

import InfrastructureSystems
import PowerSystems
import JuMP
import MathOptInterface
import PowerSystemsInvestmentsPortfolios

const IS = InfrastructureSystems
const PSY = PowerSystems
const MOI = MathOptInterface
const PSIP = PowerSystemsInvestmentsPortfolios

using DocStringExtensions

include("base/constraints.jl")
include("base/variables.jl")
include("base/expressions.jl")
include("base/optimization_container.jl")

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

end
