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

function retrieve_inv_time_series(
    d::PSIP.Technology,
    inv_ix::Int,
    time_mapping::TimeMapping,
    ::Type{V}
) where V

    if V <: Union{BuildWindCapacity, BuildSolarCapacity}
        ts_name = get_inv_default_time_series_names(typeof(d), V())
    else
        ts_name = get_inv_default_time_series_names(typeof(d))
    end
    inv_dates = get_investment_time_stamps(time_mapping)
    start_year = Dates.Year(first(inv_dates[inv_ix])).value
    return IS.get_time_series(IS.SingleTimeSeries, d, ts_name; year=string(start_year))
end

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

# TODO: Add Fixed Cost to RenewableGenerationCost !
function PSY.get_fixed(cost::PSY.RenewableGenerationCost)
    return 0.0
end
