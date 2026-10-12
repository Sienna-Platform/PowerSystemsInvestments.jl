"""
Abstract supertype for the models used to account for operation costs.
"""
abstract type OperationCostModel end

"""
Operation cost model placeholder. Not implemented.
"""
struct AggregateOperatingCost <: OperationCostModel end

"""
Operation cost model that represents the operation in each investment period with a set
of representative days (or other representative periods), each with a weight.

# Arguments

  - `representative_series::Vector{Vector{Dates.DateTime}}`: Time stamps of each
    representative period
  - `series_weights::Vector{Float64}`: Weight of each representative period. Operation
    costs and energy in a period are multiplied by its weight.

The two vectors must have the same length.

# Example

```julia
day_2030 = collect(DateTime(2030, 1, 1, 0):Hour(1):DateTime(2030, 1, 1, 23))
day_2035 = collect(DateTime(2035, 1, 1, 0):Hour(1):DateTime(2035, 1, 1, 23))
operations = OperationalRepresentativeDays([day_2030, day_2035], [365.0 * 5, 365.0 * 5])
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

"""
Operation cost model placeholder. Not implemented.
"""
struct ClusteredRepresentativeDays <: OperationCostModel
    min_consecutive_days::Int
    clustering_parameter::Int
    storage_time_aggregation::Int
end
