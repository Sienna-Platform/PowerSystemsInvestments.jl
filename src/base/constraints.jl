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

"""
Energy balance at each node and operational time step, used with
[`NodalBalanceModel`](@ref): the [`EnergyBalance`](@ref) expression must equal zero.
"""
struct NodalBalanceConstraint <: ISOPT.ConstraintType end

struct ActivePowerLimitsConstraint <: OperationVariableLimitsConstraintType end
"""
Limits the energy dispatched by a hydro technology over a representative period to a
fraction of its installed capacity. Added by [`BasicDispatchWithBudget`](@ref).
"""
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

### Requirement Constraints ###

"""
Requires the weighted generation of the technologies that contribute to an energy share
requirement to be at least a fraction of the weighted demand it applies to. Added by
[`RequirementEnergyShare`](@ref).
"""
struct EnergyShareRequirementConstraint <: ISOPT.ConstraintType end
