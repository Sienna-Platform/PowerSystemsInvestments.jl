function get_available_technologies(
    model::TechnologyModel{D, A, B, C},
    port::PSIP.Portfolio,
) where {
    D <: PSIP.Technology,
    A <: InvestmentTechnologyFormulation,
    B <: OperationsTechnologyFormulation,
    C <: FeasibilityTechnologyFormulation,
}
    return PSIP.get_technologies(PSIP.get_available, D, port;)
end

make_portfolio_filename(port::PSIP.Portfolio) = make_portfolio_filename(IS.get_uuid(port))
make_portfolio_filename(port_uuid::Union{Base.UUID, AbstractString}) =
    "portfolio-$(port_uuid).json"

function retrieve_ops_time_series(d::PSIP.Technology, op_ix::Int, time_mapping::TimeMapping)
    ts_name = get_default_time_series_names(typeof(d))
    first_t = first(get_consecutive_slices(time_mapping)[op_ix])
    year = string(Dates.Year(get_time_stamps(time_mapping)[first_t]).value)
    return IS.get_time_series(IS.SingleTimeSeries, d, ts_name; year=year, rep_day=op_ix)
end

function retrieve_ops_time_series(
    d::PSIP.Technology,
    op_ix::Int,
    time_mapping::TimeMapping,
    ts_name::String,
)
    first_t = first(get_consecutive_slices(time_mapping)[op_ix])
    year = string(Dates.Year(get_time_stamps(time_mapping)[first_t]).value)
    return IS.get_time_series(IS.SingleTimeSeries, d, ts_name; year=year, rep_day=op_ix)
end

"""
Throw an error if a time series does not start at the first time stamp of the representative
period it is used for.
"""
function check_initial_timestamp(
    time_series::IS.SingleTimeSeries,
    technology::PSIP.Technology,
    expected_timestamp::Dates.DateTime,
    op_ix::Int,
)
    initial_timestamp = first(TimeSeries.timestamp(time_series.data))
    if initial_timestamp != expected_timestamp
        error(
            "Time series $(IS.get_name(time_series)) of technology " *
            "$(PSIP.get_name(technology)) starts at $initial_timestamp but representative " *
            "period $op_ix starts at $expected_timestamp.",
        )
    end
    return
end

function _check_cumulative_limits(d::PSIP.Technology, limits::NamedTuple)
    if limits.min > limits.max
        error(
            "The minimum capacity of $(PSIP.get_name(d)) ($(limits.min)) is above its " *
            "maximum ($(limits.max)).",
        )
    end
    return
end
