### Investment Constraints ###

abstract type MaximumCumulativeInvestmentConstraint <: ISOPT.ConstraintType end

struct MaximumCumulativeCapacity <: MaximumCumulativeInvestmentConstraint end

struct SingleUnitInvestmentConstraint <: ISOPT.ConstraintType end

struct MaximumCumulativePowerCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeEnergyCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeWindCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeSolarCapacity <: MaximumCumulativeInvestmentConstraint end

struct MaximumCumulativeInverterCapacity <: MaximumCumulativeInvestmentConstraint end

struct StorageDurationLowerBoundConstraint <: ISOPT.ConstraintType end

struct StorageDurationUpperBoundConstraint <: ISOPT.ConstraintType end

### Operations Constraints ###

abstract type OperationVariableLimitsConstraintType <: ISOPT.ConstraintType end

struct SupplyDemandBalance <: ISOPT.ConstraintType end

struct SingleRegionBalanceConstraint <: ISOPT.ConstraintType end

struct MultiRegionBalanceConstraint <: ISOPT.ConstraintType end

struct NodalBalanceConstraint <: ISOPT.ConstraintType end

struct IslandBalanceConstraint <: ISOPT.ConstraintType end

struct NetworkFlowConstraint <: ISOPT.ConstraintType end

struct FlowRateConstraint <: ISOPT.ConstraintType end

struct NewCorridorBuiltConstraint <: ISOPT.ConstraintType end

struct VirtualTransactionLimitConstraint <: ISOPT.ConstraintType end

struct UnitLineBuiltConstraint <: ISOPT.ConstraintType end

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

struct MultiRegionBalanceFeasibilityConstraint <: ISOPT.ConstraintType end

struct CommittedCapacityLimitConstraint <: OperationVariableLimitsConstraintType end

struct MinimumUpTimeConstraint <: OperationVariableLimitsConstraintType end

struct MinimumDownTimeConstraint <: OperationVariableLimitsConstraintType end

struct RampRateConstraint <: OperationVariableLimitsConstraintType end

struct CommittedCapacityTrackingConstraint <: OperationVariableLimitsConstraintType end

### Requirement Constraints ###

struct EnergyShareRequirementConstraint <: ISOPT.ConstraintType end

struct CarbonCapConstraint <: ISOPT.ConstraintType end

struct CapacityReserveMarginConstraint <: ISOPT.ConstraintType end

struct CapacityRequirementConstraint <: ISOPT.ConstraintType end

struct HourlyMatchingConstraint <: ISOPT.ConstraintType end

# Duals are stored as operation entries
is_operation_entry(::Type{<:ISOPT.ConstraintType}) = true
is_investment_entry(::Type{<:ISOPT.ConstraintType}) = false
