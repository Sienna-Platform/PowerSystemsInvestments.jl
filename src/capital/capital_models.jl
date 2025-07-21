abstract type CapitalCostModel end

struct DiscountedCashFlow <: CapitalCostModel
    discount_rate::Float64
    base_year::Dates.Year
    investment_years::Vector{NTuple{2, Dates.Date}}
end
