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

# PSIP represents nodes as the base system's AC buses and zones as its aggregation topologies
get_nodes(port::PSIP.Portfolio) = PSIP.get_regions(PSY.ACBus, port)
get_zones(port::PSIP.Portfolio) = PSIP.get_regions(PSIP.get_aggregation(port), port)

make_portfolio_filename(port::PSIP.Portfolio) = make_portfolio_filename(IS.get_id(port))
make_portfolio_filename(port_id::Union{Integer, Base.UUID, AbstractString}) =
    "portfolio-$(port_id).json"

function retrieve_ops_time_series(d::PSIP.Technology, op_ix::Int, time_mapping::TimeMapping)
    ts_name = get_default_time_series_names(typeof(d))
    first_t = first(get_consecutive_slices(time_mapping)[op_ix])
    timestamp = get_time_stamps(time_mapping)[first_t]
    year = string(Dates.Year(timestamp).value)
    rep_day = Dates.month(timestamp)  # Use month instead of op_ix to handle multiple years
    return IS.get_time_series(
        IS.SingleTimeSeries,
        d,
        ts_name;
        features=Dict("year" => year, "rep_day" => rep_day),
    )
end

function retrieve_ops_time_series(
    d::PSIP.Technology,
    op_ix::Int,
    time_mapping::TimeMapping,
    ts_name::String,
)
    first_t = first(get_consecutive_slices(time_mapping)[op_ix])
    year = string(Dates.Year(get_time_stamps(time_mapping)[first_t]).value)
    return IS.get_time_series(
        IS.SingleTimeSeries,
        d,
        ts_name;
        features=Dict("year" => year, "rep_day" => op_ix),
    )
end

# TODO: Add Fixed Cost to RenewableGenerationCost !
function PSY.get_fixed(cost::PSY.RenewableGenerationCost)
    return 0.0
end
