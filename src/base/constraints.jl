### Investment Constraints ###
struct MaximumCumulativeCapacity <: ISOPT.ConstraintType end

struct MaximumCumulativePowerCapacity <: ISOPT.ConstraintType end

struct MaximumCumulativeEnergyCapacity <: ISOPT.ConstraintType end

### Operations Constraints ###

struct SupplyDemandBalance <: ISOPT.ConstraintType end

struct SingleRegionBalanceConstraint <: ISOPT.ConstraintType end

struct MultiRegionBalanceConstraint <: ISOPT.ConstraintType end

struct ActivePowerVariableLimitsConstraint <: ISOPT.ConstraintType end

struct ActivePowerLimitsConstraint <: ISOPT.ConstraintType end

struct ActivePowerLimitsConstraintUB <: ISOPT.ConstraintType end

struct ActivePowerLimitsConstraintLB <: ISOPT.ConstraintType end

struct OutputActivePowerVariableLimitsConstraint <: ISOPT.ConstraintType end

struct InputActivePowerVariableLimitsConstraint <: ISOPT.ConstraintType end

struct EnergyBalanceConstraint <: ISOPT.ConstraintType end

struct StateofChargeLimitsConstraint <: ISOPT.ConstraintType end

struct StateofChargeTargetConstraint <: ISOPT.ConstraintType end

struct InitialStateOfChargeConstraint <: ISOPT.ConstraintType end

struct SingleRegionBalanceFeasibilityConstraint <: ISOPT.ConstraintType end

struct MultiRegionBalanceFeasibilityConstraint <: ISOPT.ConstraintType end

struct EUEEstimateConstraint <: ISOPT.ConstraintType end

struct SparseChrononConstraint <: ISOPT.ConstraintType end

struct CapacityCreditConstraint <: ISOPT.ConstraintType end

struct StorageCapacityCreditConstraint <: ISOPT.ConstraintType end

struct PlanningReserveMarginConstraint <: ISOPT.ConstraintType end

struct DurationConstraint <: ISOPT.ConstraintType end

struct CCNDSurfaceConstraint <: ISOPT.ConstraintType end