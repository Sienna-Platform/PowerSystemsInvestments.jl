mutable struct InvestmentModel{S <: SolutionAlgorithm}
    name::Symbol
    template::InvestmentModelTemplate
    portfolio::PSIP.Portfolio
    internal::Union{Nothing, ISOPT.ModelInternal}
    simulation_info::SimulationInfo
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
        SimulationInfo(),
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
    output_dir::String="",
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
        output_dir=output_dir,
    )
    return InvestmentModel(template, alg, portfolio, settings, jump_model)
end

function build_impl!(::InvestmentModel{T}) where {T}
    error("Build not implemented for $T")
    return
end

function build_if_not_already_built!(model::InvestmentModel{<:SolutionAlgorithm}; kwargs...)
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
        error("build! of the $(typeof(model)) $(get_name(model)) failed: $status")
    end
    return
end

# Default implementations of getter/setter functions for InvestmentModel.
is_built(model::InvestmentModel) =
    ISOPT.get_status(get_internal(model)) == ModelBuildStatus.BUILT
isempty(model::InvestmentModel) =
    ISOPT.get_status(get_internal(model)) == ModelBuildStatus.EMPTY

get_constraints(model::InvestmentModel) =
    ISOPT.get_constraints(get_internal(model))
get_internal(model::InvestmentModel) = model.internal

function get_jump_model(model::InvestmentModel)
    return get_jump_model(ISOPT.get_container(get_internal(model)))
end

get_name(model::InvestmentModel) = model.name
get_store(model::InvestmentModel) = model.store

function get_optimization_container(model::InvestmentModel)
    return ISOPT.get_optimization_container(get_internal(model))
end

function get_container(model::InvestmentModel)
    return ISOPT.get_container(get_internal(model))
end

function get_timestamps(model::InvestmentModel)
    optimization_container = get_optimization_container(model)
    start_time = get_initial_time(optimization_container)
    resolution = get_resolution(model)
    horizon_count = get_time_steps(optimization_container)[end]
    return range(start_time; length=horizon_count, step=resolution)
end

# No Base Power for Portfolio models. Always in Natural Units.
# TODO: Decide if we will remove base power
get_problem_base_power(model::InvestmentModel) = 1.0
get_settings(model::InvestmentModel) = get_optimization_container(model).settings
get_optimizer_stats(model::InvestmentModel) =
    get_optimizer_stats(get_optimization_container(model))

get_status(model::InvestmentModel) = ISOPT.get_status(get_internal(model))
get_portfolio(model::InvestmentModel) = model.portfolio
get_template(model::InvestmentModel) = model.template
get_time_stamps(model::InvestmentModel) =
    get_time_stamps(model.internal.container.time_mapping)

get_store_params(model::InvestmentModel) =
    ISOPT.get_store_params(get_internal(model))
get_output_dir(model::InvestmentModel) = ISOPT.get_output_dir(get_internal(model))
get_recorder_dir(model::InvestmentModel) = joinpath(get_output_dir(model), "recorder")

get_variables(model::InvestmentModel) = get_variables(get_optimization_container(model))
get_duals(model::InvestmentModel) = get_duals(get_optimization_container(model))
get_initial_conditions(model::InvestmentModel) =
    get_initial_conditions(get_optimization_container(model))

get_simulation_info(model::InvestmentModel) = model.simulation_info
get_executions(model::InvestmentModel) = ISOPT.get_executions(get_internal(model))

get_run_status(model::InvestmentModel) = get_run_status(get_simulation_info(model))
set_run_status!(model::InvestmentModel, status) =
    set_run_status!(get_simulation_info(model), status)

get_initial_time(model::InvestmentModel) = get_initial_time(get_settings(model))
get_resolution(model::InvestmentModel) = get_resolution(get_settings(model))

function write_results!(
    store,
    model::InvestmentModel,
    index::Dates.Date,
    update_timestamp::Dates.Date;
    exports=nothing,
)
    if exports !== nothing
        export_params = Dict{Symbol, Any}(
            :exports => exports,
            :exports_path => joinpath(exports.path, string(get_name(model))),
            :file_type => get_export_file_type(exports),
            :resolution => get_resolution(model),
            :horizon_count => get_horizon(get_settings(model)) ÷ get_resolution(model),
        )
    else
        export_params = nothing
    end

    write_model_dual_results!(store, model, index, update_timestamp, export_params)
    write_model_variable_results!(store, model, index, update_timestamp, export_params)
    write_model_aux_variable_results!(store, model, index, update_timestamp, export_params)
    write_model_expression_results!(store, model, index, update_timestamp, export_params)
    return
end

function write_model_dual_results!(
    store,
    model::T,
    index::Dates.Date,
    update_timestamp::Dates.Date,
    export_params::Union{Dict{Symbol, Any}, Nothing},
) where {T <: InvestmentModel}
    container = get_optimization_container(model)
    model_name = get_name(model)
    if export_params !== nothing
        exports_path = joinpath(export_params[:exports_path], "duals")
        mkpath(exports_path)
    end

    for (key, constraint) in get_duals(container)
        !should_write_resulting_value(key) && continue
        data = jump_value.(constraint)
        write_result!(store, model_name, key, index, update_timestamp, data)

        if export_params !== nothing &&
           should_export_dual(export_params[:exports], index, model_name, key)
            horizon_count = export_params[:horizon_count]
            resolution = export_params[:resolution]
            file_type = export_params[:file_type]
            df = to_dataframe(jump_value.(constraint), key)
            time_col = range(index; length=horizon_count, step=resolution)
            DataFrames.insertcols!(df, 1, :DateTime => time_col)
            IS.Optimization.export_result(file_type, exports_path, key, index, df)
        end
    end
    return
end

function write_model_variable_results!(
    store,
    model::T,
    index::Dates.Date,
    update_timestamp::Dates.Date,
    export_params::Union{Dict{Symbol, Any}, Nothing},
) where {T <: InvestmentModel}
    container = get_optimization_container(model)
    model_name = get_name(model)
    if export_params !== nothing
        exports_path = joinpath(export_params[:exports_path], "variables")
        mkpath(exports_path)
    end

    if !isempty(container.primal_values_cache)
        variables = container.primal_values_cache.variables_cache
    else
        variables = get_variables(container)
    end

    for (key, variable) in variables
        !should_write_resulting_value(key) && continue
        data = jump_value.(variable)
        write_result!(store, model_name, key, index, update_timestamp, data)
        if export_params !== nothing &&
           should_export_variable(export_params[:exports], index, model_name, key)
            horizon_count = export_params[:horizon_count]
            resolution = export_params[:resolution]
            file_type = export_params[:file_type]
            df = to_dataframe(data, key)
            time_col = range(index; length=horizon_count, step=resolution)
            DataFrames.insertcols!(df, 1, :DateTime => time_col)
            IS.Optimization.export_result(file_type, exports_path, key, index, df)
        end
    end
    return
end

function write_model_aux_variable_results!(
    store,
    model::T,
    index::Dates.Date,
    update_timestamp::Dates.Date,
    export_params::Union{Dict{Symbol, Any}, Nothing},
) where {T <: InvestmentModel}
    container = get_optimization_container(model)
    model_name = get_name(model)
    if export_params !== nothing
        exports_path = joinpath(export_params[:exports_path], "aux_variables")
        mkpath(exports_path)
    end

    for (key, variable) in get_aux_variables(container)
        !should_write_resulting_value(key) && continue
        data = jump_value.(variable)
        write_result!(store, model_name, key, index, update_timestamp, data)

        if export_params !== nothing &&
           should_export_aux_variable(export_params[:exports], index, model_name, key)
            horizon_count = export_params[:horizon_count]
            resolution = export_params[:resolution]
            file_type = export_params[:file_type]
            df = to_dataframe(data, key)
            time_col = range(index; length=horizon_count, step=resolution)
            DataFrames.insertcols!(df, 1, :DateTime => time_col)
            IS.Optimization.export_result(file_type, exports_path, key, index, df)
        end
    end
    return
end

function write_model_expression_results!(
    store,
    model::T,
    index::Dates.Date,
    update_timestamp::Dates.Date,
    export_params::Union{Dict{Symbol, Any}, Nothing},
) where {T <: InvestmentModel}
    container = get_optimization_container(model)
    model_name = get_name(model)
    if export_params !== nothing
        exports_path = joinpath(export_params[:exports_path], "expressions")
        mkpath(exports_path)
    end

    if !isempty(container.primal_values_cache)
        expressions = container.primal_values_cache.expressions_cache
    else
        expressions = get_expressions(container)
    end

    for (key, expression) in expressions
        !should_write_resulting_value(key) && continue
        data = jump_value.(expression)
        write_result!(store, model_name, key, index, update_timestamp, data)

        if export_params !== nothing &&
           should_export_expression(export_params[:exports], index, model_name, key)
            horizon_count = export_params[:horizon_count]
            resolution = export_params[:resolution]
            file_type = export_params[:file_type]
            df = to_dataframe(data, key)
            time_col = range(index; length=horizon_count, step=resolution)
            DataFrames.insertcols!(df, 1, :DateTime => time_col)
            IS.Optimization.export_result(file_type, exports_path, key, index, df)
        end
    end
    return
end

function init_model_store_params!(model::InvestmentModel)
    base_power = 1.0 # Investment Models should default to Natural Units
    port_uuid = IS.make_uuid()

    store_params = ModelStoreParams(
        base_power,
        port_uuid,
        get_metadata(get_optimization_container(model)),
    )
    ISOPT.set_store_params!(get_internal(model), store_params)
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
        init_optimization_container!(
            get_optimization_container(model),
            get_template(model),
            get_portfolio(model),
        )
        @info "Initializing ModelStoreParams"
        init_model_store_params!(model)
        set_status!(model, ModelBuildStatus.IN_PROGRESS)
    end
    return
end
"""
Build the Investment Model.

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
    ISOPT.set_output_dir!(get_internal(model), output_dir)
    ISOPT.set_console_level!(get_internal(model), console_level)
    ISOPT.set_file_level!(get_internal(model), file_level)
    TimerOutputs.reset_timer!(BUILD_PROBLEMS_TIMER)
    disable_timer_outputs && TimerOutputs.disable_timer!(BUILD_PROBLEMS_TIMER)
    file_mode = "w"

    try
        try
            TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Model $(get_name(model))" begin
                build_impl!(model)
            end
            set_status!(model, ISOPT.ModelBuildStatus.BUILT)

            @info "\n$(BUILD_PROBLEMS_TIMER)\n"
        catch e
            set_status!(model, ISOPT.ModelBuildStatus.FAILED)
            bt = catch_backtrace()
            @error "InvestmentModel Build Failed" exception = e, bt
        end
    finally
        unregister_recorders!(model)
    end
    return get_status(model)
end

function solve!(
    model::InvestmentModel{<:SolutionAlgorithm};
    export_problem_results=false,
    console_level=Logging.Error,
    file_level=Logging.Info,
    disable_timer_outputs=false,
    export_optimization_problem=true,
    output_dir::Union{String, Nothing}=nothing,
    kwargs...,
)
    build_if_not_already_built!(
        model;
        console_level=console_level,
        file_level=file_level,
        disable_timer_outputs=disable_timer_outputs,
        kwargs...,
    )
    # Ensure output_dir is set on model for serialization during solve
    if !isnothing(output_dir)
        ISOPT.set_output_dir!(get_internal(model), output_dir)
    end
    ISOPT.set_console_level!(get_internal(model), console_level)
    ISOPT.set_file_level!(get_internal(model), file_level)
    TimerOutputs.reset_timer!(RUN_OPERATION_MODEL_TIMER)
    disable_timer_outputs && TimerOutputs.disable_timer!(RUN_OPERATION_MODEL_TIMER)
    file_mode = "a"
    register_recorders!(model, file_mode)
    optimizer = get(kwargs, :optimizer, nothing)
    try
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

                write_results!(get_store(model), model, current_time, current_time)
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
                results = OptimizationProblemResults(model)
                serialize_results(results, get_output_dir(model))
                export_problem_results && export_results(results)
            end
            @info "\n$(RUN_OPERATION_MODEL_TIMER)\n"
        catch e
            @error "Investment Problem solve failed" exception = (e, catch_backtrace())
            set_run_status!(model, RunStatus.FAILED)
        end
    finally
        unregister_recorders!(model)
    end

    return get_run_status(model)
end

function solve_impl!(model::InvestmentModel)
    container = get_optimization_container(model)
    status = solve_model!(container, get_portfolio(model))
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

function set_status!(model::InvestmentModel, status::Int)
    ISOPT.set_status!(get_internal(model), status)
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
    res = first(values(read_results(get_store(model), key)))
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

function register_recorders!(model::InvestmentModel, file_mode)
    try
        recorder_dir = get_recorder_dir(model)
        mkpath(recorder_dir)
        for name in ISOPT.get_recorders(get_internal(model))
            IS.register_recorder!(name; mode=file_mode, directory=recorder_dir)
        end
    catch
        # Recorders are optional; skip if not available
    end
end

function unregister_recorders!(model::InvestmentModel)
    try
        for name in ISOPT.get_recorders(get_internal(model))
            IS.unregister_recorder!(name)
        end
    catch
        # Recorders are optional; skip if not available
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
