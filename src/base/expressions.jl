abstract type InvestmentExpressionType <: ISOPT.ExpressionType end
abstract type OperationsExpressionType <: ISOPT.ExpressionType end

struct SupplyTotal <: OperationsExpressionType end
struct DemandTotal <: OperationsExpressionType end
struct ActivePowerBalance <: OperationsExpressionType end

struct CumulativeCapacity <: InvestmentExpressionType end

struct CumulativePowerCapacity <: InvestmentExpressionType end
struct CumulativeEnergyCapacity <: InvestmentExpressionType end

struct CapitalCost <: InvestmentExpressionType end
struct FixedOperationModelCost <: InvestmentExpressionType end

struct TotalCapitalCost <: ISOPT.ExpressionType end

struct VariableOMCost <: OperationsExpressionType end
