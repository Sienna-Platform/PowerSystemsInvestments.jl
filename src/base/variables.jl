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
Unserved-energy slack on a system power-balance constraint (deficit: injection < 0).
Only created when the TransportModel is built with `use_slacks = true`.
"""
struct BalanceSlackUp <: OperationsVariableType end

"""
Over-supply slack on a system power-balance constraint (surplus: injection > 0).
Only created when the TransportModel is built with `use_slacks = true`.
"""
struct BalanceSlackDown <: OperationsVariableType end

"""
Whether a PTDF branch that may not be built, a line on a corridor without existing capacity or a
unit of a discrete line, has been built by an investment period.
"""
struct BranchBuiltVariable <: InvestmentVariableType end

"""
Flow-cancelling transaction of a PTDF branch that may not be built: injected at its start node
and withdrawn at its end node, it equals the branch's flow when the branch is not built.
"""
struct VirtualTransactionVariable <: OperationsVariableType end

"""
Flow on every branch of the PTDF transport model, from its start node to its end node, computed
after the solve from the full PTDF, the net injection of every node and the virtual transactions. It is exact
whatever the PTDF cutoff, and includes the branches whose flow is not limited.
"""
struct BranchFlow <: ISOPT.AuxVariableType end

"""
Flow on each nodal AC line technology under the PTDF transport model, from its start node to its
end node, computed after the solve. A corridor's flow is shared among its existing lines and
continuous candidates in proportion to their capacity, so they are equally loaded.
"""
struct LineFlow <: ISOPT.AuxVariableType end

is_operation_entry(::Type{<:ISOPT.VariableType}) = error()
is_operation_entry(::Type{<:OperationsVariableType}) = true
is_operation_entry(::Type{<:InvestmentVariableType}) = false

is_investment_entry(::Type{<:ISOPT.VariableType}) = error()
is_investment_entry(::Type{<:OperationsVariableType}) = false
is_investment_entry(::Type{<:InvestmentVariableType}) = true

is_operation_entry(::Type{<:Union{LineFlow, BranchFlow}}) = true
is_investment_entry(::Type{<:Union{LineFlow, BranchFlow}}) = false
