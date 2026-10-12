abstract type SparseVariableType <: ISOPT.VariableType end

"""
Abstract supertype for variables indexed by investment period.
"""
abstract type InvestmentVariableType <: ISOPT.VariableType end
"""
Abstract supertype for variables indexed by operational time step.
"""
abstract type OperationsVariableType <: ISOPT.VariableType end
"""
Abstract supertype for variables indexed by feasibility time step.
"""
abstract type FeasibilityVariableType <: ISOPT.VariableType end

### Investment Variables ###

"""
Abstract supertype for variables that represent new capacity built in an investment period.
"""
abstract type BuildInvestmentVariableType <: InvestmentVariableType end

"""
Capacity of a technology built in an investment period, in MW. With
[`IntegerInvestment`](@ref), the number of units built.

Docs abbreviation: ``b``
"""
struct BuildCapacity <: BuildInvestmentVariableType end

"""
Power (discharge) capacity of a storage technology built in an investment period, in MW.

Docs abbreviation: ``b^\\text{pw}``
"""
struct BuildPowerCapacity <: BuildInvestmentVariableType end

"""
Energy capacity of a storage technology built in an investment period, in MWh.

Docs abbreviation: ``b^\\text{en}``
"""
struct BuildEnergyCapacity <: BuildInvestmentVariableType end

"""
Wind capacity of a co-located technology built in an investment period, in MW.

Docs abbreviation: ``b^\\text{wind}``
"""
struct BuildWindCapacity <: BuildInvestmentVariableType end
"""
Solar capacity of a co-located technology built in an investment period, in MW.

Docs abbreviation: ``b^\\text{solar}``
"""
struct BuildSolarCapacity <: BuildInvestmentVariableType end
"""
Inverter capacity of a co-located technology built in an investment period, in MW.

Docs abbreviation: ``b^\\text{inv}``
"""
struct BuildInverterCapacity <: BuildInvestmentVariableType end

### Operations Variables ###

"""
Active power dispatched by a supply technology in an operational time step, in MW.

Docs abbreviation: ``p``
"""
struct ActivePowerVariable <: OperationsVariableType end

"""
Active power drawn from the grid by a storage or co-located technology in an operational
time step, in MW.

Docs abbreviation: ``p^\\text{in}``
"""
struct ActiveInPowerVariable <: OperationsVariableType end

"""
Active power injected into the grid by a storage or co-located technology in an operational
time step, in MW.

Docs abbreviation: ``p^\\text{out}``
"""
struct ActiveOutPowerVariable <: OperationsVariableType end

"""
Energy stored in a storage or co-located technology at the end of an operational time step,
in MWh.

Docs abbreviation: ``e``
"""
struct StateOfChargeVariable <: OperationsVariableType end

"""
Active power charged into the storage of a co-located technology in an operational time
step, in MW.

Docs abbreviation: ``p^\\text{ch}``
"""
struct ActivePowerChargeVariable <: OperationsVariableType end

"""
Active power discharged from the storage of a co-located technology in an operational time
step, in MW.

Docs abbreviation: ``p^\\text{ds}``
"""
struct ActivePowerDischargeVariable <: OperationsVariableType end

"""
Active power produced by the wind component of a co-located technology in an operational
time step, in MW.

Docs abbreviation: ``p^\\text{wind}``
"""
struct ActivePowerWindVariable <: OperationsVariableType end

"""
Active power produced by the solar component of a co-located technology in an operational
time step, in MW.

Docs abbreviation: ``p^\\text{solar}``
"""
struct ActivePowerSolarVariable <: OperationsVariableType end

"""
Active power flow through a transport technology in an operational time step, in MW.
Positive from the start region to the end region.

Docs abbreviation: ``f``
"""
struct FlowActivePowerVariable <: OperationsVariableType end

is_operation_entry(::Type{<:ISOPT.VariableType}) = error()
is_operation_entry(::Type{<:OperationsVariableType}) = true
is_operation_entry(::Type{<:InvestmentVariableType}) = false

is_investment_entry(::Type{<:ISOPT.VariableType}) = error()
is_investment_entry(::Type{<:OperationsVariableType}) = false
is_investment_entry(::Type{<:InvestmentVariableType}) = true
