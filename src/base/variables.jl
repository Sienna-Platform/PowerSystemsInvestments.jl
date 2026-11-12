abstract type InvestmentVariableType <: VariableType end
abstract type OperationsVariableType <: VariableType end
abstract type FeasibilityVariableType <: VariableType end

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
Capacity of the supply technology of a co-located technology
"""
struct BuildSupplyCapacity <: BuildInvestmentVariableType end
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
Dispatch of the supply technology of a co-located technology at a timepoint
"""
struct ActivePowerSupplyVariable <: OperationsVariableType end

"""
Struct to dispatch the creation of bidirectional Active Power Flow Variables
"""
struct FlowActivePowerVariable <: OperationsVariableType end

####################################################################################
# Operation vs investment entry classification, used to size output storage.
# Entry types without a classification (constraints/duals, aux variables, and variables
# or expressions outside the operations/investment hierarchies) error with a message
# naming the type.
####################################################################################

is_operation_entry(::Type{T}) where {T <: OptimizationKeyType} =
    _unclassified_entry_error(T)
is_investment_entry(::Type{T}) where {T <: OptimizationKeyType} =
    _unclassified_entry_error(T)

is_operation_entry(::Type{<:OperationsVariableType}) = true
is_operation_entry(::Type{<:InvestmentVariableType}) = false

is_investment_entry(::Type{<:OperationsVariableType}) = false
is_investment_entry(::Type{<:InvestmentVariableType}) = true

function _unclassified_entry_error(::Type{T}) where {T <: VariableType}
    error(
        "Variable type $T is neither an OperationsVariableType nor an " *
        "InvestmentVariableType. Variables in an investment problem must subtype one " *
        "of the two.",
    )
end

function _unclassified_entry_error(::Type{T}) where {T <: OptimizationKeyType}
    error(
        "$T entries can't be classified as operations or investment entries: only " *
        "variables and expressions are classified.",
    )
end
