abstract type OperationCostModel end

struct AggregateOperatingCost <: OperationCostModel end

"""
Operation cost model built from representative operational slices (for example
representative days).

# Arguments

  - `representative_series::Vector{Vector{Dates.DateTime}}`: time stamps of each
    representative slice. Each slice must fall within one investment period of the capital
    model.
  - `series_weights::Vector{Float64}`: number of times each slice occurs in **one year** of
    the investment period it belongs to. Weights are per-year, not per-period: the number of
    years in the period is taken from the capital model and applied when costs are
    discounted, so it must not be included here.

The weighted duration of the slices of each investment period should add up to one year.
A period represented by a single 24-hour day uses a weight of `365`, and a period
represented by four 24-hour days uses four weights that sum to `365`. A warning is logged at
build time when this does not hold.

# Example

```julia
# Two investment periods, each represented by one 24-hour day.
operations = OperationalRepresentativeDays([day_2030, day_2035], [365.0, 365.0])
```
"""
struct OperationalRepresentativeDays <: OperationCostModel
    representative_series::Vector{Vector{Dates.DateTime}}
    series_weights::Vector{Float64}
    OperationalRepresentativeDays(representative_series, series_weights) =
        length(series_weights) == length(representative_series) ?
        new(representative_series, series_weights) :
        error("Length of weights and number of representative days are different")
end

struct ClusteredRepresentativeDays <: OperationCostModel
    min_consecutive_days::Int
    clustering_parameter::Int
    storage_time_aggregation::Int
end
