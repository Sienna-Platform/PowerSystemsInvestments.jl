struct InvestmentIntervals
    time_stamps::Vector{NTuple{2, Dates.Date}}
    map_to_operational_slices::Dict{Int, Vector{Int}}
    map_to_feasibility_slices::Dict{Int, Vector{Int}}
end

function InvestmentIntervals(::Nothing)
    return InvestmentIntervals(
        Vector{NTuple{2, Dates.Date}}(),
        Dict{Int, Vector{Int}}(),
        Dict{Int, Vector{Int}}(),
    )
end

struct OperationalPeriods
    time_stamps::Vector{Dates.DateTime}
    consecutive_slices::Vector{Vector{Int}}
    inverse_invest_mapping::Vector{Int}
    feasibility_indexes::Vector{Int}
    operational_indexes::Vector{Int}
    time_step_lengths::Vector{Float64}
end

function OperationalPeriods(::Nothing)
    return OperationalPeriods(
        Vector{Dates.DateTime}(),
        Vector{Vector{Int}}(),
        Vector{Int}(),
        Vector{Int}(),
        Vector{Int}(),
        Vector{Float64}(),
    )
end

"""
Length in hours of the time steps of a representative period. The time stamps of a period
must be evenly spaced. A period with a single time step is assumed to last one hour.
"""
function _get_time_step_length(time_stamps::Vector{Dates.DateTime})
    if length(time_stamps) == 1
        return 1.0
    end
    steps = diff(time_stamps)
    if !all(==(first(steps)), steps)
        error(
            "The time stamps of the representative period starting at " *
            "$(first(time_stamps)) are not evenly spaced.",
        )
    end
    return Dates.value(Dates.Millisecond(first(steps))) / MILLISECONDS_IN_HOUR
end

struct TimeMapping
    investment::InvestmentIntervals
    operation::OperationalPeriods
end

function TimeMapping(::Nothing)
    return TimeMapping(InvestmentIntervals(nothing), OperationalPeriods(nothing))
end

function TimeMapping(
    investment_intervals::Vector{NTuple{2, Dates.Date}},
    operational_periods::Vector{Vector{Dates.DateTime}},
    feasibility_periods::Vector{Vector{Dates.DateTime}},
)
    # TODO:
    # Validation of the dates to avoid overlaps
    # Validation of the dates to avoid gaps in the operational periods

    op_index_last_slice = length(operational_periods)
    all_operation_slices = [operational_periods; feasibility_periods]
    total_count = sum(length(x) for x in all_operation_slices)
    total_slice_count = length(operational_periods) + length(feasibility_periods)
    time_stamps = Vector{Dates.DateTime}(undef, total_count)
    consecutive_slices = Vector{Vector{Int}}(undef, total_slice_count)
    inverse_invest_mapping = Vector{Int}(undef, total_slice_count)
    time_step_lengths = Vector{Float64}(undef, total_slice_count)
    map_to_operational_slices =
        Dict{Int, Vector{Int}}(i => Vector{Int}() for i in 1:length(investment_intervals))
    map_to_feasibility_slices =
        Dict{Int, Vector{Int}}(i => Vector{Int}() for i in 1:length(investment_intervals))

    ix = 1
    slice_running_count = 0
    for (sx, slice) in enumerate(all_operation_slices)
        slice_length = length(slice)
        slice_found_in_interval = false
        for (ivx, investment_interval) in enumerate(investment_intervals)
            if first(slice) >= investment_interval[1] &&
               last(slice) <= investment_interval[2]
                if sx <= op_index_last_slice
                    push!(map_to_operational_slices[ivx], sx)
                else
                    push!(map_to_feasibility_slices[ivx], sx)
                end
                inverse_invest_mapping[sx] = ivx
                slice_found_in_interval = true
                break
            end
        end
        if !slice_found_in_interval
            error()
        end
        slice_length = length(slice)
        slice_indeces = range(slice_running_count + 1, length=slice_length)
        consecutive_slices[sx] = collect(slice_indeces)
        time_step_lengths[sx] = _get_time_step_length(slice)
        slice_running_count = last(slice_indeces)
        for time_stamp in slice
            time_stamps[ix] = time_stamp
            ix += 1
        end
    end

    op_periods = OperationalPeriods(
        time_stamps,
        consecutive_slices,
        inverse_invest_mapping,
        collect(range(start=op_index_last_slice + 1, stop=total_slice_count)),
        collect(range(1, op_index_last_slice)),
        time_step_lengths,
    )

    inv_periods = InvestmentIntervals(
        investment_intervals,
        map_to_operational_slices,
        map_to_feasibility_slices,
    )

    TimeMapping(inv_periods, op_periods)
end

get_consecutive_slices(tm::TimeMapping) = tm.operation.consecutive_slices
get_time_step_lengths(tm::TimeMapping) = tm.operation.time_step_lengths
get_time_step_length(tm::TimeMapping, op_ix::Int) = tm.operation.time_step_lengths[op_ix]
get_operational_indexes(tm::TimeMapping) = tm.operation.operational_indexes
get_feasibility_indexes(tm::TimeMapping) = tm.operation.feasibility_indexes
get_all_indexes(tm::TimeMapping) =
    [tm.operation.operational_indexes; tm.operation.feasibility_indexes]
get_time_stamps(tm::TimeMapping) = tm.operation.time_stamps
get_investment_time_stamps(tm::TimeMapping) = tm.investment.time_stamps
get_inverse_invest_mapping(tm::TimeMapping) = tm.operation.inverse_invest_mapping
get_base_date(tm::TimeMapping) = first(tm.investment.time_stamps)[1]
get_total_period_count(tm::TimeMapping) = length(tm.operation.time_stamps)
function get_total_operation_period_count(tm::TimeMapping)
    consecutive_slices = get_consecutive_slices(tm)
    operational_indexes = get_operational_indexes(tm)
    return last(consecutive_slices[last(operational_indexes)])
end
function get_total_feasibility_period_count(tm::TimeMapping)
    consecutive_slices = get_consecutive_slices(tm)
    return last(last(consecutive_slices))
end
get_total_investment_period_count(tm::TimeMapping) = length(tm.investment.time_stamps)
get_time_steps(tm::TimeMapping) = 1:get_total_period_count(tm)
get_operational_time_steps(tm::TimeMapping) = 1:get_total_operation_period_count(tm)
get_feasibility_time_steps(tm::TimeMapping) =
    (get_total_operation_period_count(tm) + 1):get_total_feasibility_period_count(tm)
get_investment_time_steps(tm::TimeMapping) = 1:get_total_investment_period_count(tm)

is_feasibility_empty(tm::TimeMapping) = isempty(tm.operation.feasibility_indexes)
get_investment_map_to_operational_slices(tm::TimeMapping) =
    tm.investment.map_to_operational_slices

"""
Time step that comes `steps_back` steps before time step `t` in the representative period
`op_ix`. Representative periods are cyclic: the time step before the first one is the last
one of the same period.
"""
function get_previous_time_step(tm::TimeMapping, op_ix::Int, t::Int, steps_back::Int=1)
    time_slices = get_consecutive_slices(tm)[op_ix]
    position = t - first(time_slices) + 1
    IS.@assert_op position >= 1
    IS.@assert_op position <= length(time_slices)
    return time_slices[mod1(position - steps_back, length(time_slices))]
end

"""
Number of time steps of the representative period `op_ix` that cover `duration` hours,
rounded to the nearest whole number and limited to the length of the period.
"""
function get_time_steps_in_duration(tm::TimeMapping, op_ix::Int, duration::Float64)
    num_time_steps = round(Int, duration / get_time_step_length(tm, op_ix))
    return clamp(num_time_steps, 0, length(get_consecutive_slices(tm)[op_ix]))
end
