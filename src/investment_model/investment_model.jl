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

# Default implementations of getter/setter functions for InvestmentModel.
is_built(model::InvestmentModel) =
    IS.Optimization.get_status(get_internal(model)) == ModelBuildStatus.BUILT
isempty(model::InvestmentModel) =
    IS.Optimization.get_status(get_internal(model)) == ModelBuildStatus.EMPTY


get_constraints(model::InvestmentModel) =
    IS.Optimization.get_constraints(get_internal(model))
get_internal(model::InvestmentModel) = model.internal

function get_jump_model(model::InvestmentModel)
    return get_jump_model(IS.Optimization.get_container(get_internal(model)))
end

get_name(model::InvestmentModel) = model.name
get_store(model::InvestmentModel) = model.store

function get_optimization_container(model::InvestmentModel)
    return IS.Optimization.get_optimization_container(get_internal(model))
end


function get_timestamps(model::InvestmentModel)
    optimization_container = get_optimization_container(model)
    start_time = get_initial_time(optimization_container)
    resolution = get_resolution(model)
    horizon_count = get_time_steps(optimization_container)[end]
    return range(start_time; length = horizon_count, step = resolution)
end

get_problem_base_power(model::InvestmentModel) = PSY.get_base_power(model.portfolio)
get_settings(model::InvestmentModel) = get_optimization_container(model).settings
get_optimizer_stats(model::InvestmentModel) = get_optimizer_stats(get_optimization_container(model))

get_status(model::InvestmentModel) = IS.Optimization.get_status(get_internal(model))
get_portfolio(model::InvestmentModel) = model.portfolio
get_template(model::InvestmentModel) = model.template

get_store_params(model::InvestmentModel) = IS.Optimization.get_store_params(get_internal(model))
get_output_dir(model::InvestmentModel) = IS.Optimization.get_output_dir(get_internal(model))
    
get_variables(model::InvestmentModel) = get_variables(get_optimization_container(model))
get_parameters(model::InvestmentModel) = get_parameters(get_optimization_container(model))
get_duals(model::InvestmentModel) = get_duals(get_optimization_container(model))
get_initial_conditions(model::InvestmentModel) =  get_initial_conditions(get_optimization_container(model))

get_run_status(model::InvestmentModel) = get_run_status(get_simulation_info(model))
set_run_status!(model::InvestmentModel, status) =
    set_run_status!(get_simulation_info(model), status)

function solve_impl!(model::InvestmentModel)
    container = get_optimization_container(model)
    status = solve_impl!(container, get_portfolio(model))
    set_run_status!(model, status)
    if status != RunStatus.SUCCESSFULLY_FINALIZED
        settings = get_settings(model)
        model_name = get_name(model)
        ts = get_current_timestamp(model)
        output_dir = get_output_dir(model)
        infeasible_opt_path = joinpath(output_dir, "infeasible_$(model_name).json")
        @error("Serializing Infeasible Problem at $(infeasible_opt_path)")
        serialize_optimization_model(container, infeasible_opt_path)
        if !get_allow_fails(settings)
            error("Solving model $(model_name) failed at $(ts)")
        else
            @error "Solving model $(model_name) failed at $(ts). Failure Allowed"
        end
    end
    return
end
    
set_console_level!(model::InvestmentModel, val) =
    IS.Optimization.set_console_level!(get_internal(model), val)
set_file_level!(model::InvestmentModel, val) =
    IS.Optimization.set_file_level!(get_internal(model), val)

function set_status!(model::InvestmentModel, status::ModelBuildStatus)
    IS.Optimization.set_status!(get_internal(model), status)
    return
end

function set_output_dir!(model::InvestmentModel, path::AbstractString)
    IS.Optimization.set_output_dir!(get_internal(model), path)
    return
end

read_dual(model::InvestmentModel, key::ConstraintKey) = _read_results(model, key)
read_parameter(model::InvestmentModel, key::ParameterKey) = _read_results(model, key)
read_aux_variable(model::InvestmentModel, key::AuxVarKey) = _read_results(model, key)
read_variable(model::InvestmentModel, key::VariableKey) = _read_results(model, key)
read_expression(model::InvestmentModel, key::ExpressionKey) = _read_results(model, key)

function _read_col_name(axes)
    if length(axes) == 1
        error("Axes of size 1 are not supported")
    end
    # Currently, variables that don't have timestamps have a dummy axes to keep
    # two axes in the Store (HDF or Memory). This if-else is used to decide if a
    # dummy axes is being used or not.
    if typeof(axes[2]) <: UnitRange{Int}
        return axes[1]
    elseif typeof(axes[2]) <: Vector{String}
        IS.@assert_op length(axes[1]) == 1
        return axes[2]
    else
        error("Second axes in store is not allowed to be $(typeof(axes[2]))")
    end
end

function _read_results(model::InvestmentModel, key::OptimizationContainerKey)
    res = read_results(get_store(model), key)
    col_name = _read_col_name(axes(res))
    return DataFrames.DataFrame(permutedims(res.data), col_name)
end

read_optimizer_stats(model::InvestmentModel) = read_optimizer_stats(get_store(model))


list_aux_variable_keys(x::InvestmentModel) =
    IS.Optimization.list_keys(get_store(x), STORE_CONTAINER_AUX_VARIABLES)
list_aux_variable_names(x::InvestmentModel) = _list_names(x, STORE_CONTAINER_AUX_VARIABLES)
list_variable_keys(x::InvestmentModel) =
    IS.Optimization.list_keys(get_store(x), STORE_CONTAINER_VARIABLES)
list_variable_names(x::InvestmentModel) = _list_names(x, STORE_CONTAINER_VARIABLES)
list_parameter_keys(x::InvestmentModel) =
    IS.Optimization.list_keys(get_store(x), STORE_CONTAINER_PARAMETERS)
list_parameter_names(x::InvestmentModel) = _list_names(x, STORE_CONTAINER_PARAMETERS)
list_dual_keys(x::InvestmentModel) =
    IS.Optimization.list_keys(get_store(x), STORE_CONTAINER_DUALS)
list_dual_names(x::InvestmentModel) = _list_names(x, STORE_CONTAINER_DUALS)
list_expression_keys(x::InvestmentModel) =
    IS.Optimization.list_keys(get_store(x), STORE_CONTAINER_EXPRESSIONS)
list_expression_names(x::InvestmentModel) = _list_names(x, STORE_CONTAINER_EXPRESSIONS)

function list_all_keys(x::InvestmentModel)
    return Iterators.flatten(
        keys(get_data_field(get_store(x), f)) for f in STORE_CONTAINERS
    )
end

function _list_names(model::InvestmentModel, container_type)
    return encode_keys_as_strings(
        IS.Optimization.list_keys(get_store(model), container_type),
    )
end
