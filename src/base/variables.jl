abstract type SparseVariableType <: ISOPT.VariableType end

abstract type InvestmentVariableType <: ISOPT.VariableType end
abstract type OperationsVariableType <: ISOPT.VariableType end
abstract type FeasibilityVariableType <: ISOPT.VariableType end

### Investment Variables ###

abstract type BuildInvestmentVariableType <: InvestmentVariableType end

"""
Total installed capacity for a technology
"""
struct BuildCapacity <: BuildInvestmentVariableType end

"""
Total installed capacity for a technology
"""
struct BuildPowerCapacity <: BuildInvestmentVariableType end

"""
Total installed capacity for a technology
"""
struct BuildEnergyCapacity <: BuildInvestmentVariableType end

"""
TODO
"""
struct BuildWindCapacity <: BuildInvestmentVariableType end
"""
TODO
"""
struct BuildSolarCapacity <: BuildInvestmentVariableType end
"""
TODO
"""
struct BuildInverterCapacity <: BuildInvestmentVariableType end

### Operations Variables ###

"""
Dispatch of a technology at a timepoint
"""
struct ActivePowerVariable <: OperationsVariableType end

"""
Dispatch of a technology at a timepoint
"""
struct ActiveInPowerVariable <: OperationsVariableType end

"""
Dispatch of a technology at a timepoint
"""
struct ActiveOutPowerVariable <: OperationsVariableType end

"""
energy stored in Storage technology at a timepoint
"""
struct StateOfChargeVariable <: OperationsVariableType end

"""
Dispatch of a technology at a timepoint
"""
struct ActivePowerChargeVariable <: OperationsVariableType end

"""
Dispatch of a technology at a timepoint
"""
struct ActivePowerDischargeVariable <: OperationsVariableType end

"""
Dispatch of a technology at a timepoint
"""
struct ActivePowerWindVariable <: OperationsVariableType end

"""
Dispatch of a technology at a timepoint
"""
struct ActivePowerSolarVariable <: OperationsVariableType end

"""
Struct to dispatch the creation of bidirectional Active Power Flow Variables
"""
struct FlowActivePowerVariable <: OperationsVariableType end

"""
Flow from the start to the end of a transport technology
"""
struct FlowActivePowerFromToVariable <: OperationsVariableType end

"""
Flow from the end to the start of a transport technology
"""
struct FlowActivePowerToFromVariable <: OperationsVariableType end

"""
Amount of installed capacity that has been committed for dispatch at a timepoint
"""
struct CommittedCapacityVariable <: OperationsVariableType end

"""
Amount of capacity that has been shut down at a timepoint
"""
struct ShutDownCapacityVariable <: OperationsVariableType end

"""
Amount of capacity that has been started up at a timepoint
"""
struct StartUpCapacityVariable <: OperationsVariableType end

"""
Demand left unserved in one tier of a demand's unserved demand cost (MW)
"""
struct UnservedDemandVariable <: OperationsVariableType end

"""
Flexible demand deferred out of a time step: served later, or already served earlier (MW)
"""
struct DemandDeferredVariable <: OperationsVariableType end

"""
Flexible demand served in a time step instead of its original one (MW)
"""
struct DemandRecoveredVariable <: OperationsVariableType end

"""
Flexible demand deferred and not yet served (MWh); negative when demand was served early
"""
struct DemandBacklogVariable <: OperationsVariableType end

"""
Whether a prospective PTDF branch is built by an investment period.
"""
struct BranchBuiltVariable <: InvestmentVariableType end

"""
Transaction that cancels the flow of an unbuilt PTDF branch.
"""
struct VirtualTransactionVariable <: OperationsVariableType end

"""
Exact flow on every PTDF branch, computed after the solve.
"""
struct BranchFlow <: ISOPT.AuxVariableType end

"""
Flow on each nodal AC line under the PTDF model, computed after the solve. A corridor's flow
is split among its lines in proportion to their capacity.
"""
struct LineFlow <: ISOPT.AuxVariableType end

is_operation_entry(::Type{<:ISOPT.VariableType}) = error()
is_operation_entry(::Type{<:OperationsVariableType}) = true
is_operation_entry(::Type{<:InvestmentVariableType}) = false

is_investment_entry(::Type{<:ISOPT.VariableType}) = error()
is_investment_entry(::Type{<:OperationsVariableType}) = false
is_investment_entry(::Type{<:InvestmentVariableType}) = true

"""
Shortfall of a requirement (MWh per year for energy requirements), priced in the objective
when its `RequirementModel` uses slacks
"""
struct RequirementSlackVariable <: OperationsVariableType end

is_operation_entry(::Type{<:Union{LineFlow, BranchFlow}}) = true
is_investment_entry(::Type{<:Union{LineFlow, BranchFlow}}) = false
