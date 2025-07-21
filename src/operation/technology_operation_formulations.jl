### Operations Formulations ###

struct BasicDispatch <: OperationsTechnologyFormulation end

abstract type OperationsStorageFormulation <: OperationsTechnologyFormulation end
struct ChronologicalStorageDispatch <: OperationsStorageFormulation end
struct CyclicalStorageDispatch <: OperationsStorageFormulation end

abstract type OperationsColocatedFormulation <: OperationsTechnologyFormulation end
struct ChronologicalColocatedDispatch <: OperationsColocatedFormulation end
struct CyclicalColocatedDispatch <: OperationsColocatedFormulation end

### Feasibility Formulations ###

struct BasicDispatchFeasibility <: FeasibilityTechnologyFormulation end
