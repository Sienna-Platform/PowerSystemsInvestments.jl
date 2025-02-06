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

struct OutputActivePowerVariableLimitsConstraint <: ISOPT.ConstraintType end

struct InputActivePowerVariableLimitsConstraint <: ISOPT.ConstraintType end

struct EnergyBalanceConstraint <: ISOPT.ConstraintType end

struct StateofChargeLimitsConstraint <: ISOPT.ConstraintType end

struct SingleRegionBalanceFeasibilityConstraint <: ISOPT.ConstraintType end
