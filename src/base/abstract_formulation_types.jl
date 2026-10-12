"""
Abstract supertype of all technology formulations.
"""
abstract type AbstractTechnologyFormulation end

"""
Abstract supertype for formulations of the investment decision of a technology, such as
[`ContinuousInvestment`](@ref) or [`IntegerInvestment`](@ref).
"""
abstract type InvestmentTechnologyFormulation <: AbstractTechnologyFormulation end
"""
Abstract supertype for formulations of how a technology is dispatched in the operational
periods, such as [`BasicDispatch`](@ref).
"""
abstract type OperationsTechnologyFormulation <: AbstractTechnologyFormulation end
"""
Abstract supertype for formulations of how a technology participates in the feasibility
periods, such as [`BasicDispatchFeasibility`](@ref).
"""
abstract type FeasibilityTechnologyFormulation <: AbstractTechnologyFormulation end

"""
Abstract supertype for formulations of a requirement (policy), such as
[`RequirementEnergyShare`](@ref).
"""
abstract type RequirementFormulation end
