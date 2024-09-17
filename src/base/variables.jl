abstract type SparseVariableType <: ISOPT.VariableType end

abstract type InvestmentVariableType <: ISOPT.VariableType end
abstract type OperationsVariableType <: ISOPT.VariableType end

### Investment Variables ###

"""
Total installed capacity for a technology
"""
struct BuildCapacity <: InvestmentVariableType end

"""
Total installed capacity for a technology
"""
struct BuildPowerCapacity <: InvestmentVariableType end

"""
Total installed capacity for a technology
"""
struct BuildEnergyCapacity <: InvestmentVariableType end

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
struct EnergyVariable <: OperationsVariableType end
