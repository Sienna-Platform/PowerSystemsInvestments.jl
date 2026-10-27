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
