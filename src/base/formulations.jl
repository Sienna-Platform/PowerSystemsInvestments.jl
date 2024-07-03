abstract type InvestmentTechnologyFormulation end
abstract type OperationsTechnologyFormulation end

struct ContinuousInvestment <: InvestmentTechnologyFormulation end
struct IntegerInvestment <: InvestmentTechnologyFormulation end

struct BasicDispatch <: OperationsTechnologyFormulation end
struct NoDispatch <: OperationsTechnologyFormulation end
