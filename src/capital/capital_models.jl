abstract type CapitalCostModel end

struct DiscountedCashFlow <: CapitalCostModel
    discount_rate::Float64
end
