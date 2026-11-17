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

# Time series of a technology for a representative period. It must have one value per time step
# of the period, starting at its first time stamp.
function retrieve_ops_time_series(
    d::PSIP.Technology,
    op_ix::Int,
    time_mapping::TimeMapping,
    ts_name::String=get_default_time_series_names(typeof(d)),
)
    time_slices = get_consecutive_slices(time_mapping)[op_ix]
    first_timestamp = get_time_stamps(time_mapping)[first(time_slices)]
    time_series = IS.get_time_series(
        IS.SingleTimeSeries,
        d,
        ts_name;
        year=string(Dates.year(first_timestamp)),
        rep_day=op_ix,
    )
    check_time_series(time_series, d, first_timestamp, length(time_slices), op_ix)
    return time_series
end

function check_time_series(
    time_series::IS.SingleTimeSeries,
    technology::PSIP.Technology,
    expected_timestamp::Dates.DateTime,
    expected_length::Int,
    op_ix::Int,
)
    description = "Time series $(IS.get_name(time_series)) of technology $(PSIP.get_name(technology))"
    initial_timestamp = first(TimeSeries.timestamp(time_series.data))
    if initial_timestamp != expected_timestamp
        error(
            "$description starts at $initial_timestamp but representative period $op_ix " *
            "starts at $expected_timestamp.",
        )
    end
    if length(time_series.data) != expected_length
        error(
            "$description has $(length(time_series.data)) values but representative " *
            "period $op_ix has $expected_length time steps.",
        )
    end
    return
end
