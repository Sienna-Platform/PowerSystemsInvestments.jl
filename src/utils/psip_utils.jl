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

make_portfolio_filename(port::PSIP.Portfolio) = make_portfolio_filename(PSIP.get_name(port))
make_portfolio_filename(port_uuid::Union{Base.UUID, AbstractString}) =
    "portfolio-$(port_uuid).json"

function retrieve_ops_time_series(d::PSIP.Technology, op_ix::Int, time_mapping::TimeMapping)
    ts_name = get_default_time_series_names(typeof(d))
    first_t = first(get_consecutive_slices(time_mapping)[op_ix])
    year = string(Dates.Year(get_time_stamps(time_mapping)[first_t]).value)
    return IS.get_time_series(
        IS.SingleTimeSeries,
        d,
        ts_name;
        features=Dict("year" => year, "rep_day" => op_ix),
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

"""
Resolve a technology's capacity limits to a single `(min, max)` pair.

PSIP allows resource technology capacity limits to be either one `MinMax` or a per-topology
`Dict{PSY.Topology, MinMax}`. A technology modeled in a single region uses the entry for that
region.
"""
resolve_capacity_limits(limits::NamedTuple{(:min, :max)}, ::PSIP.Technology) = limits

function resolve_capacity_limits(limits::Dict, d::PSIP.Technology)
    regions = PSIP.get_region(d)
    if length(regions) != 1
        throw(
            ArgumentError(
                "Per-topology capacity limits for $(PSIP.get_name(d)) require the technology " *
                "to be in exactly one region; it has $(length(regions)).",
            ),
        )
    end
    region = only(regions)
    haskey(limits, region) || throw(
        ArgumentError(
            "Capacity limits for $(PSIP.get_name(d)) have no entry for region $(PSY.get_name(region)).",
        ),
    )
    return limits[region]
end
