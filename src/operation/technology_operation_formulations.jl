### Operations Formulations ###

struct BasicDispatch <: OperationsTechnologyFormulation end
struct BasicDispatchWithBudget <: OperationsTechnologyFormulation end

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
