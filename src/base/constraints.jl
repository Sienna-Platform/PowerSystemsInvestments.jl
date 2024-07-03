# Investment Constraints
struct MaximumCumulativeCapacity <: ISOPT.ConstraintType end
struct MinimumCumulativeCapacity <: ISOPT.ConstraintType end

# Dispatch Constraints
struct MaximumDispatch <: ISOPT.ConstraintType end
struct SupplyDemandBalance <: ISOPT.ConstraintType end
