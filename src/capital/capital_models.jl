"""
Abstract supertype for the models used to account for capital costs.
"""
abstract type CapitalCostModel end

"""
Capital cost model that annualizes investment costs and discounts them to a base year.
It also defines the investment periods of the model.

# Arguments

  - `discount_rate::Float64`: Discount rate
  - `base_year::Dates.Year`: Year that costs are discounted to
  - `investment_years::Vector{NTuple{2, Dates.Date}}`: Start and end dates of each
    investment period, in chronological order

!!! note

    The discount rate and base year used in the objective function are currently read
    from the `Portfolio`. Only `investment_years` is read from this struct.

# Example

```julia
capital = DiscountedCashFlow(
    0.07,
    Year(2025),
    [(Date(2030, 1, 1), Date(2034, 12, 31)), (Date(2035, 1, 1), Date(2039, 12, 31))],
)
```
"""
struct DiscountedCashFlow <: CapitalCostModel
    discount_rate::Float64
    base_year::Dates.Year
    investment_years::Vector{NTuple{2, Dates.Date}}
end
