abstract type OperationCostModel end

struct AggregateOperatingCost <: OperationCostModel end

struct ClusteredRepresentativeDays <: OperationCostModel
    min_consequetive_days::Int
    clutering_parameter::Int
    storage_time_aggregation::Int
end
