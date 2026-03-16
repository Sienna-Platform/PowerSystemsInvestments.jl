abstract type InvestmentExpressionType <: ExpressionType end
abstract type OperationsExpressionType <: ExpressionType end
abstract type FeasibilityExpressionType <: ExpressionType end

abstract type CumulativeInvestmentExpressionType <: InvestmentExpressionType end

struct SupplyTotal <: OperationsExpressionType end
struct DemandTotal <: OperationsExpressionType end
struct EnergyBalance <: OperationsExpressionType end

struct CumulativeCapacity <: CumulativeInvestmentExpressionType end

struct CumulativePowerCapacity <: CumulativeInvestmentExpressionType end
struct CumulativeEnergyCapacity <: CumulativeInvestmentExpressionType end
struct CumulativeWindCapacity <: CumulativeInvestmentExpressionType end
struct CumulativeSolarCapacity <: CumulativeInvestmentExpressionType end
struct CumulativeInverterCapacity <: CumulativeInvestmentExpressionType end

struct CapitalCost <: InvestmentExpressionType end
struct FixedOperationModelCost <: InvestmentExpressionType end

struct TotalCapitalCost <: ExpressionType end

struct VariableOMCost <: OperationsExpressionType end

struct FeasibilitySurplus <: FeasibilityExpressionType end

should_write_resulting_value(::Type{CumulativeCapacity}) = true
should_write_resulting_value(::Type{CumulativePowerCapacity}) = true
should_write_resulting_value(::Type{CumulativeEnergyCapacity}) = true
should_write_resulting_value(::Type{CumulativeSolarCapacity}) = true
should_write_resulting_value(::Type{CumulativeWindCapacity}) = true
should_write_resulting_value(::Type{CumulativeInverterCapacity}) = true

is_operation_entry(::Type{<:OperationsExpressionType}) = true
is_operation_entry(::Type{<:InvestmentExpressionType}) = false

is_investment_entry(::Type{<:OperationsExpressionType}) = false
is_investment_entry(::Type{<:InvestmentExpressionType}) = true
