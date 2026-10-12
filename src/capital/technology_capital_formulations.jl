### Capital Formulations ###
"""
Investment formulation for demand technologies. Demand is an input, not a decision, so no
investment variables are created.
"""
struct StaticLoadInvestment <: InvestmentTechnologyFormulation end
"""
Investment formulation in which the capacity built in each investment period is a
continuous variable, in MW (or MWh for energy capacity).
"""
struct ContinuousInvestment <: InvestmentTechnologyFormulation end
"""
Investment formulation in which the build decision in each investment period is an integer
number of units. The capacity added is the number of units times the unit size of the
technology.
"""
struct IntegerInvestment <: InvestmentTechnologyFormulation end
"""
Investment formulation in which the build decision in each investment period is binary:
either nothing is built or the maximum capacity of the technology is built.
"""
struct BinaryInvestment <: InvestmentTechnologyFormulation end
