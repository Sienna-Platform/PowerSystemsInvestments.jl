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

"""
Binary investment decision variable for discrete capacity options (0 or 1)
"""
struct BinaryInvestmentDecision <: BuildInvestmentVariableType end

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

is_operation_entry(::Type{<:ISOPT.VariableType}) = error()
is_operation_entry(::Type{<:OperationsVariableType}) = true
is_operation_entry(::Type{<:InvestmentVariableType}) = false

is_investment_entry(::Type{<:ISOPT.VariableType}) = error()
is_investment_entry(::Type{<:OperationsVariableType}) = false
is_investment_entry(::Type{<:InvestmentVariableType}) = true
