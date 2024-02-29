module PowerSystemsInvestments

import InfrastructureSystems
import PowerSystems
import JuMP
import MathOptInterface

const IS = InfrastructureSystems
const PSY = PowerSystems
const MOI = MathOptInterface

using DocStringExtensions

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

end
