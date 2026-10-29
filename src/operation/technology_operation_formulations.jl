### Operations Formulations ###

struct BasicDispatch <: OperationsTechnologyFormulation end
struct BasicDispatchWithBudget <: OperationsTechnologyFormulation end
struct BasicDispatchWithLosses <: OperationsTechnologyFormulation end

# Demand that can go unserved at the price of its unserved demand cost
struct UnservedDemandDispatch <: OperationsTechnologyFormulation end
# Unserved demand, plus shifting of the flexible share of demand within time windows
struct FlexibleDemandDispatch <: OperationsTechnologyFormulation end
# Consumption of an end-use technology, valued by what it produces
struct EndUseDispatch <: OperationsTechnologyFormulation end

abstract type ThermalCommitmentFormulation <: OperationsTechnologyFormulation end
struct ContinuousThermalCommitment <: ThermalCommitmentFormulation end
struct IntegerUnitCommitment <: ThermalCommitmentFormulation end

abstract type OperationsStorageFormulation <: OperationsTechnologyFormulation end
struct ChronologicalStorageDispatch <: OperationsStorageFormulation end
struct CyclicalStorageDispatch <: OperationsStorageFormulation end

abstract type OperationsColocatedFormulation <: OperationsTechnologyFormulation end
struct ChronologicalColocatedDispatch <: OperationsColocatedFormulation end
struct CyclicalColocatedDispatch <: OperationsColocatedFormulation end

### Feasibility Formulations ###

struct BasicDispatchFeasibility <: FeasibilityTechnologyFormulation end
