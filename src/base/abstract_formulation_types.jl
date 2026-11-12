####################################################################################
# Formulation abstract types for Investment problems
# Siblings of IS.Optimization's AbstractDeviceFormulation / AbstractServiceFormulation
# (which the operation-side formulations subtype).
####################################################################################

abstract type AbstractTechnologyFormulation <: AbstractDeviceFormulation end

abstract type InvestmentTechnologyFormulation <: AbstractTechnologyFormulation end
abstract type OperationsTechnologyFormulation <: AbstractTechnologyFormulation end
abstract type FeasibilityTechnologyFormulation <: AbstractTechnologyFormulation end
abstract type RequirementFormulation <: AbstractServiceFormulation end
