### Investment Constraints ###

abstract type MaximumCumulativeInvestmentConstraint <: ConstraintType end

struct MaximumCumulativeCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativePowerCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeEnergyCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeWindCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeSolarCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeInverterCapacity <: MaximumCumulativeInvestmentConstraint end

### Operations Constraints ###

abstract type OperationVariableLimitsConstraintType <: ConstraintType end

struct SupplyDemandBalance <: ConstraintType end

struct SingleRegionBalanceConstraint <: ConstraintType end

struct MultiRegionBalanceConstraint <: ConstraintType end

struct ActivePowerLimitsConstraint <: OperationVariableLimitsConstraintType end

struct OutputActivePowerVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct InputActivePowerVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ActivePowerDischargeVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ActivePowerChargeVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ActivePowerWindVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ActivePowerSolarVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct StateOfChargeLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ColocatedInternalBalanceConstraint <: ConstraintType end

struct EnergyBalanceConstraint <: ConstraintType end

struct SingleRegionBalanceFeasibilityConstraint <: ConstraintType end
