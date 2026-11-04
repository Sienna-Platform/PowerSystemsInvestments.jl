"""
Investment periods and the operational and feasibility slices that belong to each of them.

# Fields

  - `time_stamps::Vector{NTuple{2, Dates.Date}}`: Start and end dates of each investment
    period.
  - `map_to_operational_slices::Dict{Int, Vector{Int}}`: Operational slice indexes of each
    investment period.
  - `map_to_feasibility_slices::Dict{Int, Vector{Int}}`: Feasibility slice indexes of each
    investment period.
"""
struct InvestmentIntervals
    time_stamps::Vector{NTuple{2, Dates.Date}}
    map_to_operational_slices::Dict{Int, Vector{Int}}
    map_to_feasibility_slices::Dict{Int, Vector{Int}}
end

"""
Time steps of the operational and feasibility slices, in the order the model indexes them.

# Fields

  - `time_stamps::Vector{Dates.DateTime}`: Time stamp of every time step. Operational slices
    come first, then feasibility slices.
  - `consecutive_slices::Vector{UnitRange{Int}}`: Time steps of each slice.
  - `inverse_invest_mapping::Vector{Int}`: Investment period of each slice.
  - `feasibility_indexes::Vector{Int}`: Indexes of the feasibility slices.
  - `operational_indexes::Vector{Int}`: Indexes of the operational slices.
  - `weights::Vector{Float64}`: Number of times each slice occurs per year. Feasibility
    slices weigh 0.0 because they add nothing to annual totals.
"""
struct OperationalPeriods
    time_stamps::Vector{Dates.DateTime}
    consecutive_slices::Vector{UnitRange{Int}}
    inverse_invest_mapping::Vector{Int}
    feasibility_indexes::Vector{Int}
    operational_indexes::Vector{Int}
    weights::Vector{Float64}
end

"""
Investment periods (upper periods) and the operational and feasibility slices (blocks) that
belong to them, with the weight of each slice.
"""
struct InvestmentTimeMapping
    investment::InvestmentIntervals
    operation::OperationalPeriods
end

"""
Build an `InvestmentTimeMapping` and check that it is consistent.

# Arguments

  - `investment_intervals`: Start and end dates of each investment period.
  - `operational_periods`: Time stamps of each operational slice.
  - `feasibility_periods`: Time stamps of each feasibility slice.
  - `operational_weights`: Number of times each operational slice occurs per year. Defaults
    to 1.0 per slice.

Every slice must lie entirely inside one investment interval.
"""
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
        if isnothing(ivx)
            if sx <= op_index_last_slice
                period = "Operational period $sx"
            else
                period = "Feasibility period $(sx - op_index_last_slice)"
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
    validate_time_mapping(tm)
    return tm
end

"""
Build the `InvestmentTimeMapping` described by the capital, operation and feasibility models
of `template`.
"""
function InvestmentTimeMapping(template::InvestmentModelTemplate)
    operation_model = get_operation_model(template)
    return InvestmentTimeMapping(
        get_capital_model(template).investment_years,
        operation_model.representative_series,
        get_feasibility_model(template).sample_periods;
        operational_weights=operation_model.series_weights,
    )
end

get_consecutive_slices(tm::InvestmentTimeMapping) = tm.operation.consecutive_slices
get_operational_indexes(tm::InvestmentTimeMapping) = tm.operation.operational_indexes
get_feasibility_indexes(tm::InvestmentTimeMapping) = tm.operation.feasibility_indexes
get_all_indexes(tm::InvestmentTimeMapping) =
    [tm.operation.operational_indexes; tm.operation.feasibility_indexes]
get_operational_weights(tm::InvestmentTimeMapping) = tm.operation.weights
get_time_stamps(tm::InvestmentTimeMapping) = tm.operation.time_stamps
get_investment_time_stamps(tm::InvestmentTimeMapping) = tm.investment.time_stamps
get_inverse_invest_mapping(tm::InvestmentTimeMapping) = tm.operation.inverse_invest_mapping
get_base_date(tm::InvestmentTimeMapping) = first(tm.investment.time_stamps)[1]
get_total_period_count(tm::InvestmentTimeMapping) = length(tm.operation.time_stamps)
function get_total_operation_period_count(tm::InvestmentTimeMapping)
    operational_indexes = get_operational_indexes(tm)
    if isempty(operational_indexes)
        return 0
    end
    return last(get_consecutive_slices(tm)[last(operational_indexes)])
end
get_total_feasibility_period_count(tm::InvestmentTimeMapping) = get_total_period_count(tm)
get_total_investment_period_count(tm::InvestmentTimeMapping) =
    length(tm.investment.time_stamps)
get_time_steps(tm::InvestmentTimeMapping) = 1:get_total_period_count(tm)
get_operational_time_steps(tm::InvestmentTimeMapping) =
    1:get_total_operation_period_count(tm)
get_feasibility_time_steps(tm::InvestmentTimeMapping) =
    (get_total_operation_period_count(tm) + 1):get_total_feasibility_period_count(tm)
get_investment_time_steps(tm::InvestmentTimeMapping) =
    1:get_total_investment_period_count(tm)
is_feasibility_empty(tm::InvestmentTimeMapping) = isempty(tm.operation.feasibility_indexes)
get_investment_map_to_operational_slices(tm::InvestmentTimeMapping) =
    tm.investment.map_to_operational_slices

"""
Check that the slices cover the time steps in order, without gaps or overlaps, that each
slice belongs to a valid investment period, and that every slice has a weight.
"""
function validate_time_mapping(tm::InvestmentTimeMapping)
    slices = get_consecutive_slices(tm)
    invest_mapping = get_inverse_invest_mapping(tm)
    if length(invest_mapping) != length(slices)
        error(
            "The time mapping has $(length(slices)) slices but $(length(invest_mapping)) " *
            "investment period indexes.",
        )
    end
    next_step = 1
    for (sx, slice) in enumerate(slices)
        if isempty(slice) || first(slice) != next_step
            error(
                "Slice $sx covers time steps $slice; slices must be non-empty and start " *
                "at time step $next_step.",
            )
        end
        next_step = last(slice) + 1
    end
    step_count = get_total_period_count(tm)
    if next_step != step_count + 1
        error(
            "The slices cover $(next_step - 1) time steps but the time mapping has " *
            "$step_count time stamps.",
        )
    end
    period_count = get_total_investment_period_count(tm)
    for (sx, ivx) in enumerate(invest_mapping)
        if !(1 <= ivx <= period_count)
            error("Slice $sx belongs to investment period $ivx, outside 1:$period_count.")
        end
    end
    weight_count = length(get_operational_weights(tm))
    if weight_count != length(slices)
        error("The time mapping has $(length(slices)) slices but $weight_count weights.")
    end
    return
end

"""
Warn when the operational weights of an investment period do not represent one year.

Weights are the number of times each representative slice occurs per year. Operation costs
are multiplied by the number of years of the investment period when they are discounted, so
weights that already include the period length would count those costs more than once.
"""
function check_operational_weights(time_mapping::InvestmentTimeMapping)
    operational_weights = get_operational_weights(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    time_stamps = get_time_stamps(time_mapping)
    investment_time_stamps = get_investment_time_stamps(time_mapping)
    investment_to_operational_ixs = get_investment_map_to_operational_slices(time_mapping)
    for stage in get_investment_time_steps(time_mapping)
        stage_operational_indexes = investment_to_operational_ixs[stage]
        isempty(stage_operational_indexes) && continue
        represented_hours = 0.0
        for op_ix in stage_operational_indexes
            time_slices = consecutive_slices[op_ix]
            # A slice with a single time step is assumed to last one hour.
            hours_per_step = 1.0
            if length(time_slices) > 1
                step = time_stamps[time_slices[2]] - time_stamps[time_slices[1]]
                hours_per_step = Dates.value(Dates.Millisecond(step)) / 3.6e6
            end
            represented_hours +=
                operational_weights[op_ix] * length(time_slices) * hours_per_step
        end
        represented_years = represented_hours / HOURS_PER_YEAR
        if abs(represented_years - 1.0) > OPERATIONAL_WEIGHTS_TOLERANCE
            @warn "The operational weights of investment period $(investment_time_stamps[stage]) " *
                  "represent $(round(represented_years; digits=3)) years of operation. " *
                  "Weights must be per-year: the weighted duration of the representative " *
                  "slices of each investment period should add up to one year. The length " *
                  "of the period is applied separately when costs are discounted."
        end
    end
    return
end
