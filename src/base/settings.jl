# PSI uses IOM.Settings directly.
# This file provides convenience constructors and PSI-specific accessors.

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

# Re-export commonly used accessors that don't clash
get_horizon(settings::IOM.Settings) = IOM.get_horizon(settings)
get_resolution(settings::IOM.Settings) = IOM.get_resolution(settings)
get_initial_time(settings::IOM.Settings) = IOM.get_initial_time(settings)
get_optimizer(settings::IOM.Settings) = IOM.get_optimizer(settings)
get_direct_mode_optimizer(settings::IOM.Settings) = IOM.get_direct_mode_optimizer(settings)
get_optimizer_solve_log_print(settings::IOM.Settings) = IOM.get_optimizer_solve_log_print(settings)
get_detailed_optimizer_stats(settings::IOM.Settings) = IOM.get_detailed_optimizer_stats(settings)
get_calculate_conflict(settings::IOM.Settings) = IOM.get_calculate_conflict(settings)
get_deserialize_initial_conditions(settings::IOM.Settings) = IOM.get_deserialize_initial_conditions(settings)
get_store_variable_names(settings::IOM.Settings) = IOM.get_store_variable_names(settings)
get_check_numerical_bounds(settings::IOM.Settings) = IOM.get_check_numerical_bounds(settings)
get_ext(settings::IOM.Settings) = IOM.get_ext(settings)

set_horizon!(settings::IOM.Settings, horizon::Dates.TimePeriod) = IOM.set_horizon!(settings, horizon)
set_resolution!(settings::IOM.Settings, resolution::Dates.TimePeriod) = IOM.set_resolution!(settings, resolution)
set_initial_time!(settings::IOM.Settings, initial_time::Dates.DateTime) = IOM.set_initial_time!(settings, initial_time)

copy_for_serialization(settings::IOM.Settings) = IOM.copy_for_serialization(settings)
log_values(settings::IOM.Settings) = IOM.log_values(settings)
