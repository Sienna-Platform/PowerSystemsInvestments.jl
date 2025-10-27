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
    time_mapping::TimeMapping,
    ::Type{V},
) where {V <: BuildInvestmentVariableType}
    ts_name = get_inv_default_time_series_names(typeof(d), V())
    ts_available_names = IS.get_name.(IS.get_time_series_keys(d))
    if ts_name ∈ ts_available_names
        return IS.get_time_series(IS.SingleTimeSeries, d, ts_name)
    else
        nothing
    end
end

function retrieve_inv_time_series_value(ts::IS.SingleTimeSeries, inv_year::Int)
    time_array = ts.data
    timestamps = TimeSeries.timestamp(time_array)
    values = TimeSeries.values(time_array)
    ix = findfirst(t -> Dates.year(t) == inv_year, timestamps)
    if ix !== nothing
        return values[ix]
    else
        @warn "Year $inv_year not found in investment time series $(ts.name). Returning 1.0 as scaling factor."
        return 1.0
    end
end

function retrieve_inv_time_series_value(::Nothing, ::Int)
    return 1.0
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

function get_wacc(tech_financials::PSIP.TechnologyFinancialData)
    dr = tech_financials.debt_rate
    tr = tech_financials.tax_rate
    re = tech_financials.return_on_equity
    df = tech_financials.debt_fraction
    ef = 1.0 - df
    if df > 1.0 || df < 0.0
        error("Debt fraction must be between 0.0 and 1.0")
    end
    return df * dr * (1.0 - tr) + ef * re
end
