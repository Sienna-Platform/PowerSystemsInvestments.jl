### Operations Formulations ###

struct BasicDispatch <: OperationsTechnologyFormulation end

abstract type OperationsStorageFormulation <: OperationsTechnologyFormulation end
struct ChronologicalStorageDispatch <: OperationsStorageFormulation end
struct CyclicalStorageDispatch <: OperationsStorageFormulation end

### Feasibility Formulations ###

struct BasicDispatchFeasibility <: FeasibilityTechnologyFormulation end
