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

# IOM's generic `Settings`/`OptimizationContainer` constructors query the "system" through these
# accessors. PSI's "system" is the `Portfolio`; implementing the methods here keeps IOM free of any
# PowerSystemsInvestmentsPortfolios dependency. Investment models operate in natural units
# (base_power = 1.0).
IOM.get_base_power(::PSIP.Portfolio) = 1.0
IS.stores_time_series_in_memory(p::PSIP.Portfolio) = IS.stores_time_series_in_memory(p.data)

function retrieve_ops_time_series(d::PSIP.Technology, op_ix::Int, time_mapping::TimeMapping)
    ts_name = get_default_time_series_names(typeof(d))
    first_t = first(get_consecutive_slices(time_mapping)[op_ix])
    year = string(Dates.Year(get_time_stamps(time_mapping)[first_t]).value)
    return IS.get_time_series(IS.SingleTimeSeries, d, ts_name; features=Dict("year"=>year, "rep_day"=>op_ix))
end

function retrieve_ops_time_series(
    d::PSIP.Technology,
    op_ix::Int,
    time_mapping::TimeMapping,
    ts_name::String,
)
    first_t = first(get_consecutive_slices(time_mapping)[op_ix])
    year = string(Dates.Year(get_time_stamps(time_mapping)[first_t]).value)
    return IS.get_time_series(IS.SingleTimeSeries, d, ts_name; features=Dict("year"=>year, "rep_day"=>op_ix))
end

# Defaults for a system-less model (a `nothing` "system"): let the generic `Settings` and
# `OptimizationContainer` constructors build a container without a domain system (e.g. for unit
# tests). Downstream packages add methods for their own "system" types.
IOM.get_base_power(::Nothing) = 1.0
IOM.stores_time_series_in_memory(::Nothing) = false