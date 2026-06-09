### Investment Constraints ###

abstract type MaximumCumulativeInvestmentConstraint <: ISOPT.ConstraintType end

struct MaximumCumulativeCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativePowerCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeEnergyCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeWindCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeSolarCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeInverterCapacity <: MaximumCumulativeInvestmentConstraint end

### Operations Constraints ###

abstract type OperationVariableLimitsConstraintType <: ISOPT.ConstraintType end

struct SupplyDemandBalance <: ISOPT.ConstraintType end

struct SingleRegionBalanceConstraint <: ISOPT.ConstraintType end

struct MultiRegionBalanceConstraint <: ISOPT.ConstraintType end

struct NodalBalanceConstraint <: ISOPT.ConstraintType end

struct ActivePowerLimitsConstraint <: OperationVariableLimitsConstraintType end
struct HydroEnergyBudgetConstraint <: OperationVariableLimitsConstraintType end

struct FlowActivePowerLowerBoundConstraint <: OperationVariableLimitsConstraintType end

struct FlowActivePowerUpperBoundConstraint <: OperationVariableLimitsConstraintType end

struct OutputActivePowerVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct InputActivePowerVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ActivePowerDischargeVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ActivePowerChargeVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ActivePowerWindVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ActivePowerSolarVariableLimitsConstraint <: OperationVariableLimitsConstraintType end

struct StateOfChargeLimitsConstraint <: OperationVariableLimitsConstraintType end

struct ColocatedInternalBalanceConstraint <: ISOPT.ConstraintType end

struct EnergyBalanceConstraint <: ISOPT.ConstraintType end

struct SingleRegionBalanceFeasibilityConstraint <: ISOPT.ConstraintType end
