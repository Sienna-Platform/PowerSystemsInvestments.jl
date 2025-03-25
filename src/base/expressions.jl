abstract type InvestmentExpressionType <: ISOPT.ExpressionType end
abstract type OperationsExpressionType <: ISOPT.ExpressionType end
abstract type FeasibilityExpressionType <: ISOPT.ExpressionType end

struct SupplyTotal <: OperationsExpressionType end
struct DemandTotal <: OperationsExpressionType end
struct EnergyBalance <: OperationsExpressionType end

struct CumulativeCapacity <: InvestmentExpressionType end

struct CumulativePowerCapacity <: InvestmentExpressionType end
struct CumulativeEnergyCapacity <: InvestmentExpressionType end

struct CapitalCost <: InvestmentExpressionType end
struct FixedOperationModelCost <: InvestmentExpressionType end

struct TotalCapitalCost <: ISOPT.ExpressionType end

struct VariableOMCost <: OperationsExpressionType end

struct FeasibilitySurplus <: FeasibilityExpressionType end

should_write_resulting_value(::Type{CumulativeCapacity}) = true
should_write_resulting_value(::Type{CumulativePowerCapacity}) = true
should_write_resulting_value(::Type{CumulativeEnergyCapacity}) = true

is_operation_entry(::Type{<:OperationsExpressionType}) = true
is_operation_entry(::Type{<:InvestmentExpressionType}) = false

is_investment_entry(::Type{<:OperationsExpressionType}) = false
is_investment_entry(::Type{<:InvestmentExpressionType}) = true
