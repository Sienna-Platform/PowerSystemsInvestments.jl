### Operations Formulations ###

"""
Operations formulation in which a technology is dispatched between zero and its
cumulative installed capacity in each time step, scaled by a capacity factor time series
where the technology has one.
"""
struct BasicDispatch <: OperationsTechnologyFormulation end
"""
Operations formulation that adds an energy budget to [`BasicDispatch`](@ref): the energy
dispatched over each representative period is limited to a fraction of the installed
capacity. Implemented for `SupplyTechnology{HydroDispatch}`.
"""
struct BasicDispatchWithBudget <: OperationsTechnologyFormulation end

"""
Abstract supertype for the operations formulations of storage technologies.
"""
abstract type OperationsStorageFormulation <: OperationsTechnologyFormulation end
"""
Storage operations formulation in which the state of charge is carried from one
representative period to the next within an investment period.
"""
struct ChronologicalStorageDispatch <: OperationsStorageFormulation end
"""
Storage operations formulation in which each representative period is cyclic: the state
of charge at the start of the period is linked to the state of charge at its end.
"""
struct CyclicalStorageDispatch <: OperationsStorageFormulation end

"""
Abstract supertype for the operations formulations of co-located technologies.
"""
abstract type OperationsColocatedFormulation <: OperationsTechnologyFormulation end
"""
Co-located technology operations formulation in which the storage state of charge is
carried from one representative period to the next within an investment period.
"""
struct ChronologicalColocatedDispatch <: OperationsColocatedFormulation end
"""
Co-located technology operations formulation in which the storage state of charge is
cyclic within each representative period.
"""
struct CyclicalColocatedDispatch <: OperationsColocatedFormulation end

### Feasibility Formulations ###

"""
Feasibility formulation in which the installed capacity of a technology counts towards
covering demand in the feasibility periods.
"""
struct BasicDispatchFeasibility <: FeasibilityTechnologyFormulation end
