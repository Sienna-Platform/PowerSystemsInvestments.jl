abstract type CapitalCostModel end

"""
Capital model that discounts every cost to `base_year`, the model base year. Each technology
discounts at the rates in its own `TechnologyFinancialData`.
"""
struct DiscountedCashFlow <: CapitalCostModel
    base_year::Dates.Year
    investment_years::Vector{NTuple{2, Dates.Date}}
end
