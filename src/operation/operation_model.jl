abstract type OperationCostModel end

struct AggregateOperatingCost <: OperationCostModel end

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
