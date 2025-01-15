abstract type SparseVariableType <: ISOPT.VariableType end

abstract type InvestmentVariableType <: ISOPT.VariableType end
abstract type OperationsVariableType <: ISOPT.VariableType end
abstract type FeasibilityVariableType <: ISOPT.VariableType end

### Investment Variables ###

"""
Total installed capacity for a technology
"""
struct BuildCapacity <: InvestmentVariableType end

"""
Total installed charge/discharge capacity for a storage technology
"""
struct BuildPowerCapacity <: InvestmentVariableType end

"""
Total installed energy capacity for a storage technology
"""
struct BuildEnergyCapacity <: InvestmentVariableType end

### Operations Variables ###

"""
Dispatch of a technology at a timepoint
"""
struct ActivePowerVariable <: OperationsVariableType end

"""
Charging of a storage technology at a timepoint
"""
struct ActiveInPowerVariable <: OperationsVariableType end

"""
Discharging of a storage technology at a timepoint
"""
struct ActiveOutPowerVariable <: OperationsVariableType end

"""
Total energy stored in Storage technology at a timepoint
"""
struct EnergyVariable <: OperationsVariableType end

"""
Voltage angle in each region/node
"""
struct VoltageAngle <: OperationsVariableType end

is_operation_entry(::Type{<:ISOPT.VariableType}) = error()
is_operation_entry(::Type{<:OperationsVariableType}) = true
is_operation_entry(::Type{<:InvestmentVariableType}) = false

is_investment_entry(::Type{<:ISOPT.VariableType}) = error()
is_investment_entry(::Type{<:OperationsVariableType}) = false
is_investment_entry(::Type{<:InvestmentVariableType}) = true
