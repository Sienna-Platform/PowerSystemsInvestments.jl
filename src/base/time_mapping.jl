struct InvestmentIntervals
    time_stamps::Vector{NTuple{2, Dates.Date}}
    map_to_operational_slices::Dict{Int, Vector{Int}}
    map_to_feasibility_slices::Dict{Int, Vector{Int}}
end

struct OperationalPeriods
    time_stamps::Vector{Dates.DateTime}
    consecutive_slices::Vector{UnitRange{Int}}
    inverse_invest_mapping::Vector{Int}
    feasibility_indexes::Vector{Int}
    operational_indexes::Vector{Int}
    # One per slice; feasibility slices weigh 0.0 since they add nothing to annual totals
    weights::Vector{Float64}
end

# Investment intervals (upper periods) containing operational and feasibility slices (blocks)
struct InvestmentTimeMapping <: IOM.AbstractTimeMapping
    investment::InvestmentIntervals
    operation::OperationalPeriods
end

function InvestmentTimeMapping(
    investment_intervals::Vector{NTuple{2, Dates.Date}},
    operational_periods::Vector{Vector{Dates.DateTime}},
    feasibility_periods::Vector{Vector{Dates.DateTime}};
    operational_weights::Vector{Float64}=ones(length(operational_periods)),
)
    if length(operational_weights) != length(operational_periods)
        error(
            "operational_weights length ($(length(operational_weights))) must match the " *
            "number of operational slices ($(length(operational_periods)))",
        )
    end

    op_index_last_slice = length(operational_periods)
    all_operation_slices = [operational_periods; feasibility_periods]
    total_slice_count = length(all_operation_slices)
    time_stamps = Vector{Dates.DateTime}()
    consecutive_slices = Vector{UnitRange{Int}}(undef, total_slice_count)
    inverse_invest_mapping = Vector{Int}(undef, total_slice_count)
    map_to_operational_slices =
        Dict{Int, Vector{Int}}(i => Vector{Int}() for i in 1:length(investment_intervals))
    map_to_feasibility_slices =
        Dict{Int, Vector{Int}}(i => Vector{Int}() for i in 1:length(investment_intervals))

    for (sx, slice) in enumerate(all_operation_slices)
        ivx = findfirst(
            interval -> first(slice) >= interval[1] && last(slice) <= interval[2],
            investment_intervals,
        )
        if ivx === nothing
            period = if sx <= op_index_last_slice
                "Operational period $sx"
            else
                "Feasibility period $(sx - op_index_last_slice)"
            end
            error(
                "$period ($(first(slice)) to $(last(slice))) does not fall within any " *
                "investment interval. Every operational and feasibility period must lie " *
                "entirely inside one of the investment intervals: $(investment_intervals)",
            )
        end
        if sx <= op_index_last_slice
            push!(map_to_operational_slices[ivx], sx)
        else
            push!(map_to_feasibility_slices[ivx], sx)
        end
        inverse_invest_mapping[sx] = ivx
        consecutive_slices[sx] = range(length(time_stamps) + 1; length=length(slice))
        append!(time_stamps, slice)
    end

    tm = InvestmentTimeMapping(
        InvestmentIntervals(
            investment_intervals,
            map_to_operational_slices,
            map_to_feasibility_slices,
        ),
        OperationalPeriods(
            time_stamps,
            consecutive_slices,
            inverse_invest_mapping,
            collect((op_index_last_slice + 1):total_slice_count),
            collect(1:op_index_last_slice),
            [operational_weights; zeros(length(feasibility_periods))],
        ),
    )
    IOM.validate_time_mapping(tm)
    return tm
end

function InvestmentTimeMapping(template::InvestmentModelTemplate)
    operation_model = template.operation_model
    return InvestmentTimeMapping(
        template.capital_model.investment_years,
        operation_model.representative_series,
        template.feasibility_model.sample_periods;
        operational_weights=operation_model.series_weights,
    )
end

# AbstractTimeMapping interface
IOM.get_period_count(tm::InvestmentTimeMapping) = length(tm.investment.time_stamps)
IOM.get_block_ranges(tm::InvestmentTimeMapping) = tm.operation.consecutive_slices
IOM.get_block_period_index(tm::InvestmentTimeMapping) = tm.operation.inverse_invest_mapping
IOM.get_timestamps(tm::InvestmentTimeMapping) = tm.operation.time_stamps
IOM.get_block_weights(tm::InvestmentTimeMapping) = tm.operation.weights

# Investment names for the generic accessors
get_consecutive_slices(tm::InvestmentTimeMapping) = IOM.get_block_ranges(tm)
get_inverse_invest_mapping(tm::InvestmentTimeMapping) = IOM.get_block_period_index(tm)
get_investment_time_steps(tm::InvestmentTimeMapping) = IOM.get_periods(tm)
get_operational_weights(tm::InvestmentTimeMapping) = IOM.get_block_weights(tm)
get_operational_weights(container::OptimizationContainer) =
    get_operational_weights(get_time_mapping(container))

get_operational_indexes(tm::InvestmentTimeMapping) = tm.operation.operational_indexes
get_feasibility_indexes(tm::InvestmentTimeMapping) = tm.operation.feasibility_indexes
get_all_indexes(tm::InvestmentTimeMapping) =
    [tm.operation.operational_indexes; tm.operation.feasibility_indexes]
get_investment_time_stamps(tm::InvestmentTimeMapping) = tm.investment.time_stamps
get_investment_map_to_operational_slices(tm::InvestmentTimeMapping) =
    tm.investment.map_to_operational_slices
is_feasibility_empty(tm::InvestmentTimeMapping) = isempty(tm.operation.feasibility_indexes)

IOM.get_base_date(tm::InvestmentTimeMapping) = first(tm.investment.time_stamps)[1]
function IOM.get_total_operation_period_count(tm::InvestmentTimeMapping)
    operational_indexes = get_operational_indexes(tm)
    isempty(operational_indexes) && return 0
    return last(get_consecutive_slices(tm)[last(operational_indexes)])
end
get_feasibility_time_steps(tm::InvestmentTimeMapping) =
    (get_total_operation_period_count(tm) + 1):length(get_timestamps(tm))
