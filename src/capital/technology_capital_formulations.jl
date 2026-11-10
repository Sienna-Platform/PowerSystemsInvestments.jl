### Capital Formulations ###
struct StaticLoadInvestment <: InvestmentTechnologyFormulation end
struct ContinuousInvestment <: InvestmentTechnologyFormulation end
struct IntegerInvestment <: InvestmentTechnologyFormulation end
struct BinaryInvestment <: InvestmentTechnologyFormulation end
# Capacity built only by retrofitting existing capacity of another technology (RetrofitPotential)
struct RetrofitInvestment <: InvestmentTechnologyFormulation end
