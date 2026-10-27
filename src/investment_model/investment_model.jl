function build_impl!(::InvestmentModel{T}) where {T}
    error("Build not implemented for $T")
    return
end

function build_if_not_already_built!(
    model::InvestmentModel{<:AbstractInvestmentProblem};
    kwargs...,
)
    status = get_status(model)
    if status == ModelBuildStatus.EMPTY
        if !haskey(kwargs, :output_dir)
            error(
                "'output_dir' must be provided as a kwarg if the model build status is $status",
            )
        else
            new_kwargs = Dict(k => v for (k, v) in kwargs if k != :optimizer)
            status = build!(model; new_kwargs...)
        end
    end
    if status != ModelBuildStatus.BUILT
        error("build! of the $(typeof(model)) $(IOM.get_name(model)) failed: $status")
    end
    return
end

# Called by the InvestmentModel constructor. Operational time series are read per
# representative period during the build, so this only checks that there is data to read.
function IOM.validate_time_series!(model::InvestmentModel{<:AbstractInvestmentProblem})
    counts = IS.get_time_series_counts(get_portfolio(model).data)
    if counts.static_time_series_count < 1
        error(
            "The portfolio does not contain any time series data. An InvestmentModel can't be built.",
        )
    end
    return
end

function init_model_store_params!(model::InvestmentModel)
    base_power = 1.0 # Investment Models should default to Natural Units
    port_uuid = IS.make_uuid()
    container = get_optimization_container(model)
    time_mapping = get_time_mapping(container)
    horizon_count = length(get_time_steps(time_mapping))
    resolution = get_resolution(model)
    interval = resolution
    num_executions = get_executions(model)

    store_params = ModelStoreParams(
        num_executions,
        horizon_count,
        interval,
        resolution,
        base_power,
        port_uuid,
        get_metadata(container),
    )
    set_store_params!(get_internal(model), store_params)
    return
end

function build_pre_step!(model::InvestmentModel)
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Build pre-step" begin
        # TODO: add template validation
        #validate_template(model)
        if !isempty(model)
            @info "OptimizationProblem status not ModelBuildStatus.EMPTY. Resetting"

            reset!(model)
        end
        # Initial time are set here because the information is specified in the
        # Simulation Sequence object and not at the problem creation.
        @info "Initializing Optimization Container For an InvestmentModel"
        container = get_optimization_container(model)
        IOM.init_optimization_container!(
            container,
            get_template(model),
            get_portfolio(model),
        )
        set_time_mapping!(container, InvestmentTimeMapping(get_template(model)))
        @info "Initializing ModelStoreParams"
        init_model_store_params!(model)
        set_status!(model, ModelBuildStatus.IN_PROGRESS)
    end
    return
end
"""
Build the Investment Model.

# Arguments

    - `model::InvestmentModel{<:AbstractInvestmentProblem}`: InvestmentModel object
    - `output_dir::String`: Output directory for results
    - `console_level = Logging.Error`:
    - `file_level = Logging.Info`:
    - `disable_timer_outputs = false` : Enable/Disable timing outputs
"""
function build!(
    model::InvestmentModel{<:AbstractInvestmentProblem};
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
                TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Model $(IOM.get_name(model))" begin
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

function reset!(model::InvestmentModel{<:AbstractInvestmentProblem})
    was_built_for_recurrent_solves = built_for_recurrent_solves(model)
    if was_built_for_recurrent_solves
        IOM.set_execution_count!(model, 0)
    end
    port = IOM.get_portfolio(model)
    IOM.set_container!(
        get_internal(model),
        OptimizationContainer(port, get_settings(model), nothing, IS.SingleTimeSeries),
    )
    get_optimization_container(model).built_for_recurrent_solves =
        was_built_for_recurrent_solves
    internal = get_internal(model)
    IOM.set_initial_conditions_model_container!(internal, nothing)
    IOM.empty_time_series_cache!(model)
    empty!(get_store(model))
    set_status!(model, ModelBuildStatus.EMPTY)
    return
end

function solve!(
    model::InvestmentModel{<:AbstractInvestmentProblem};
    export_problem_results=false,
    console_level=Logging.Error,
    file_level=Logging.Info,
    disable_timer_outputs=false,
    export_optimization_problem=true,
    kwargs...,
)
    build_if_not_already_built!(
        model;
        console_level=console_level,
        file_level=file_level,
        disable_timer_outputs=disable_timer_outputs,
        kwargs...,
    )
    set_console_level!(model, console_level)
    set_file_level!(model, file_level)
    TimerOutputs.reset_timer!(RUN_OPERATION_MODEL_TIMER)
    disable_timer_outputs && TimerOutputs.disable_timer!(RUN_OPERATION_MODEL_TIMER)
    file_mode = "a"
    register_recorders!(model, file_mode)
    logger = configure_logging(get_internal(model), PROBLEM_LOG_FILENAME, file_mode)
    optimizer = get(kwargs, :optimizer, nothing)
    try
        Logging.with_logger(logger) do
            try
                initialize_storage!(
                    get_store(model),
                    get_optimization_container(model),
                    get_store_params(model),
                )
                TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Solve" begin
                    @warn "todo: add pre-solve model check back in"
                    #_pre_solve_model_checks(model, optimizer)
                    solve_impl!(model)
                    container = get_optimization_container(model)
                    time_mapping = get_time_mapping(container)
                    current_time = get_base_date(time_mapping)

                    timestamp = Dates.DateTime(current_time)
                    IOM.write_outputs!(get_store(model), model, timestamp, timestamp)
                    write_optimizer_stats!(
                        get_store(model),
                        get_optimizer_stats(model),
                        current_time,
                    )
                end

                if export_optimization_problem
                    TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Serialize" begin
                        serialize_problem(model; optimizer=optimizer)
                        serialize_optimization_model(model)
                    end
                end
                TimerOutputs.@timeit RUN_OPERATION_MODEL_TIMER "Results processing" begin
                    results = OptimizationProblemOutputs(model)
                    serialize_outputs(results, get_output_dir(model))
                    export_problem_results && export_outputs(results)
                end
                @info "\n$(RUN_OPERATION_MODEL_TIMER)\n"
            catch e
                @error "Investment Problem solve failed" exception = (e, catch_backtrace())
                set_run_status!(model, RunStatus.FAILED)
            end
        end
    finally
        unregister_recorders!(model)
        close(logger)
    end

    return get_run_status(model)
end

function solve_impl!(model::InvestmentModel)
    container = get_optimization_container(model)
    status = solve_model!(container, get_portfolio(model))
    set_run_status!(model, status)
    if status != RunStatus.SUCCESSFULLY_FINALIZED
        model_name = IOM.get_name(model)
        ts = get_initial_time(model)
        settings = get_settings(model)
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

read_dual(model::InvestmentModel, key::ConstraintKey) = _read_results(model, key)
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
    arr = IOM.read_outputs(get_store(model), key)
    col_names = string.(_read_col_name(axes(arr)))
    df_wide = DataFrames.DataFrame(permutedims(arr.data), col_names)
    df_wide.time_index = 1:size(arr.data, 2)
    return DataFrames.stack(
        df_wide,
        DataFrames.Not(:time_index);
        variable_name=:name,
        value_name=:value,
    )
end

read_optimizer_stats(model::InvestmentModel) = read_optimizer_stats(get_store(model))

list_aux_variable_keys(x::InvestmentModel) = list_keys(get_store(x), AuxVariableType)
list_aux_variable_names(x::InvestmentModel) = _list_names(x, AuxVariableType)
list_variable_keys(x::InvestmentModel) = list_keys(get_store(x), VariableType)
list_variable_names(x::InvestmentModel) = _list_names(x, VariableType)
list_dual_keys(x::InvestmentModel) = list_keys(get_store(x), ConstraintType)
list_dual_names(x::InvestmentModel) = _list_names(x, ConstraintType)
list_expression_keys(x::InvestmentModel) = list_keys(get_store(x), ExpressionType)
list_expression_names(x::InvestmentModel) = _list_names(x, ExpressionType)

function list_all_keys(x::InvestmentModel)
    return Iterators.flatten(
        keys(get_data_field(get_store(x), f)) for f in STORE_CONTAINERS
    )
end

function _list_names(
    model::InvestmentModel,
    container_type::Type{T},
) where {T <: OptimizationKeyType}
    return encode_keys_as_strings(list_keys(get_store(model), container_type))
end

function register_recorders!(model::InvestmentModel, file_mode)
    recorder_dir = get_recorder_dir(model)
    mkpath(recorder_dir)
    for name in get_recorders(get_internal(model))
        IS.register_recorder!(name; mode=file_mode, directory=recorder_dir)
    end
end

function unregister_recorders!(model::InvestmentModel)
    for name in get_recorders(get_internal(model))
        IS.unregister_recorder!(name)
    end
end

const _JUMP_MODEL_FILENAME = "jump_model.json"

function serialize_optimization_model(model::InvestmentModel)
    serialize_optimization_model(
        get_optimization_container(model),
        joinpath(get_output_dir(model), _JUMP_MODEL_FILENAME),
    )
    return
end
