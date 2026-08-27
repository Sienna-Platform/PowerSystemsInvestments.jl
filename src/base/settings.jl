# PSI uses IOM.Settings directly.
# This file provides convenience constructors and PSI-specific accessors.

# PSI-facing `Settings` constructors (thin wrappers over `IOM.Settings`). With a portfolio, the
# portfolio acts as the "system"; with no argument, IOM's system-less default is used.
#TODO: Determine if this is needed and reconcile IOM.Settings and InvestmentSettings
Settings(portfolio; kwargs...) = IOM.Settings(portfolio; kwargs...)
Settings(; kwargs...) = IOM.Settings(; kwargs...)

function InvestmentSettings(
    portfolio;
    initial_time::Dates.DateTime=UNSET_INI_TIME,
    time_series_cache_size::Int=IS.TIME_SERIES_CACHE_SIZE_BYTES,
    horizon::Dates.Period=UNSET_HORIZON,
    resolution::Dates.Period=UNSET_RESOLUTION,
    optimizer=nothing,
    direct_mode_optimizer::Bool=false,
    optimizer_solve_log_print::Bool=false,
    detailed_optimizer_stats::Bool=false,
    calculate_conflict::Bool=false,
    portfolio_to_file::Bool=true,
    deserialize_initial_conditions::Bool=false,
    check_numerical_bounds=true,
    store_variable_names=false,
    ext=Dict{String, Any}(),
)
    # Use IOM.Settings constructor with portfolio as "system"
    return IOM.Settings(
        portfolio;
        initial_time=initial_time,
        time_series_cache_size=time_series_cache_size,
        horizon=horizon,
        resolution=resolution,
        optimizer=optimizer,
        direct_mode_optimizer=direct_mode_optimizer,
        optimizer_solve_log_print=optimizer_solve_log_print,
        detailed_optimizer_stats=detailed_optimizer_stats,
        calculate_conflict=calculate_conflict,
        system_to_file=portfolio_to_file,
        deserialize_initial_conditions=deserialize_initial_conditions,
        check_numerical_bounds=check_numerical_bounds,
        store_variable_names=store_variable_names,
        ext=ext,
    )
end

# PSI-specific alias
get_portfolio_to_file(settings::IOM.Settings) = IOM.get_system_to_file(settings)
