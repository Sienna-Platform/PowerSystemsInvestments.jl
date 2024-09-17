mutable struct InvestmentModel{S <: SolutionAlgorithm}
    name::Symbol
    template::InvestmentModelTemplate
    portfolio::PSIP.Portfolio
    internal::Union{Nothing, ISOPT.ModelInternal}
    store::InvestmentModelStore
    ext::Dict{String, Any}
end

function InvestmentModel(
    template::AbstractInvestmentModelTemplate,
    M::Type{SingleInstanceSolve},
    portfolio::PSIP.Portfolio,
    settings::Settings,
    jump_model::Union{Nothing, JuMP.Model}=nothing;
)
    internal = ISOPT.ModelInternal(SingleOptimizationContainer(settings, jump_model))

    model = InvestmentModel{M}(
        :CEM,
        template,
        portfolio,
        internal,
        InvestmentModelStore(),
        Dict{String, Any}(),
    )
    return model
end

function InvestmentModel(
    template::AbstractInvestmentModelTemplate,
    alg::Type{SingleInstanceSolve},
    portfolio::PSIP.Portfolio,
    jump_model::Union{Nothing, JuMP.Model}=nothing;
    name=nothing,
    optimizer=nothing,
    horizon=UNSET_HORIZON,
    resolution=UNSET_RESOLUTION,
    portfolio_to_file=true,
    optimizer_solve_log_print=false,
    detailed_optimizer_stats=false,
    calculate_conflict=false,
    direct_mode_optimizer=false,
    store_variable_names=false,
    check_numerical_bounds=true,
    initial_time=UNSET_INI_TIME,
    time_series_cache_size::Int=IS.TIME_SERIES_CACHE_SIZE_BYTES,
)
    settings = Settings(
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
        portfolio_to_file=portfolio_to_file,
        check_numerical_bounds=check_numerical_bounds,
        store_variable_names=store_variable_names,
    )
    return InvestmentModel(template, alg, portfolio, settings, jump_model)
end

function build_impl!(::InvestmentModel{T}) where {T}
    error("Build not implemented for $T")
    return
end

"""
Build the Invesment Model.

# Arguments

  - `model::InvestmentModel{<:SolutionAlgorithm}`: InvestmentModel object
  - `output_dir::String`: Output directory for results
  - `console_level = Logging.Error`:
  - `file_level = Logging.Info`:
  - `disable_timer_outputs = false` : Enable/Disable timing outputs
"""
function build!(
    model::InvestmentModel{<:SolutionAlgorithm};
    output_dir::String,
    console_level=Logging.Error,
    file_level=Logging.Info,
    disable_timer_outputs=false,
)
    mkpath(output_dir)
    set_output_dir!(model, output_dir)
    set_console_level!(model, console_level)
    set_file_level!(model, file_level)
    TimerOutputs.reset_timer!(BUILD_PROBLEMS_TIMER)
    disable_timer_outputs && TimerOutputs.disable_timer!(BUILD_PROBLEMS_TIMER)
    file_mode = "w"

    logger = IS.configure_logging(get_internal(model), PROBLEM_LOG_FILENAME, file_mode)
    try
        Logging.with_logger(logger) do
            try
                TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Problem $(get_name(model))" begin
                    build_impl!(model)
                end
                set_status!(model, ModelBuildStatus.BUILT)
                @info "\n$(BUILD_PROBLEMS_TIMER)\n"
            catch e
                set_status!(model, ModelBuildStatus.FAILED)
                bt = catch_backtrace()
                @error "InvestmentModel Build Failed" exception = e, bt
            end
        end
    finally
        unregister_recorders!(model)
        close(logger)
    end
    return get_status(model)
end
