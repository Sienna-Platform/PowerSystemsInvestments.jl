mutable struct ObjectiveFunction
    expression::JuMP.AbstractJuMPScalar
    capital_terms::JuMP.AbstractJuMPScalar
    operation_terms::JuMP.AbstractJuMPScalar
    sense::MOI.OptimizationSense
    function ObjectiveFunction(
        capital_terms::JuMP.AbstractJuMPScalar,
        operation_terms::JuMP.AbstractJuMPScalar,
        sense::MOI.OptimizationSense=MOI.MIN_SENSE,
    )
        new(capital_terms, operation_terms, sense)
    end
end

get_capital_terms(v::ObjectiveFunction) = v.capital_terms
get_operation_terms(v::ObjectiveFunction) = v.operation_terms

function get_objective_expression(v::ObjectiveFunction)
    return JuMP.add_to_expression!(v.capital_terms, v.operation_terms)
end
get_sense(v::ObjectiveFunction) = v.sense

set_sense!(v::ObjectiveFunction, sense::MOI.OptimizationSense) = v.sense = sense

function ObjectiveFunction()
    return ObjectiveFunction(
        zero(JuMP.GenericAffExpr{Float64, JuMP.VariableRef}),
        zero(JuMP.AffExpr),
        true,
    )
end

Base.@kwdef mutable struct MultiOptimizationContainer{T <: SolutionAlgorithm} <: ISOPT.AbstractModelContainer
    main_problem::OptimizationContainer
    subproblems::Dict{String, OptimizationContainer}
    time_steps::UnitRange{Int}
    resolution::Dates.TimePeriod
    settings::Settings
    settings_copy::Settings
    variables::Dict{ISOPT.VariableKey, AbstractArray}
    aux_variables::Dict{ISOPT.AuxVarKey, AbstractArray}
    duals::Dict{ISOPT.ConstraintKey, AbstractArray}
    constraints::Dict{ISOPT.ConstraintKey, AbstractArray}
    objective_function::ObjectiveFunction
    expressions::Dict{ISOPT.ExpressionKey, AbstractArray}
    parameters::Dict{ISOPT.ParameterKey, ParameterContainer}
    optimizer_stats::ISOPT.OptimizerStats  # TODO: needs custom struct for decomposition
    metadata::ISOPT.OptimizationContainerMetadata
    default_time_series_type::Type{<:PSY.TimeSeriesData}  # Maybe isn't needed here
    mpi_info::Union{Nothing, MpiInfo}
end

function MultiOptimizationContainer(
    ::Type{T},
    sys::PSY.System,
    settings::Settings,
    ::Type{U},
    subproblem_keys::Vector{String},
) where {T <: SolutionAlgorithm, U <: PSY.TimeSeriesData}
    resolution = PSY.get_time_series_resolution(sys)
    if isabstracttype(U)
        error("Default Time Series Type $U can't be abstract")
    end

    # define dictionary containing the optimization container for the subregion
    subproblems = Dict(
        k => OptimizationContainer(sys, settings, nothing, U) for k in subproblem_keys
    )

    return MultiOptimizationContainer{T}(;
        main_problem=OptimizationContainer(sys, settings, nothing, U),
        subproblems=subproblems,
        time_steps=1:1,
        resolution=IS.time_period_conversion(resolution),
        settings=settings,
        settings_copy=copy_for_serialization(settings),
        variables=Dict{VariableKey, AbstractArray}(),
        aux_variables=Dict{AuxVarKey, AbstractArray}(),
        duals=Dict{ConstraintKey, AbstractArray}(),
        constraints=Dict{ConstraintKey, AbstractArray}(),
        objective_function=ObjectiveFunction(),
        expressions=Dict{ExpressionKey, AbstractArray}(),
        parameters=Dict{ParameterKey, ParameterContainer}(),
        base_power=PSY.get_base_power(sys),
        optimizer_stats=OptimizerStats(),
        built_for_recurrent_solves=false,
        metadata=OptimizationContainerMetadata(),
        default_time_series_type=U,
        mpi_info=nothing,
    )
end

function get_container_keys(container::MultiOptimizationContainer)
    return Iterators.flatten(keys(getfield(container, f)) for f in STORE_CONTAINERS)
end

get_default_time_series_type(container::MultiOptimizationContainer) =
    container.default_time_series_type
get_duals(container::MultiOptimizationContainer) = container.duals
get_expressions(container::MultiOptimizationContainer) = container.expressions
get_initial_conditions(container::MultiOptimizationContainer) =
    container.initial_conditions
get_initial_conditions_data(container::MultiOptimizationContainer) =
    container.initial_conditions_data
get_initial_time(container::MultiOptimizationContainer) =
    get_initial_time(container.settings)
get_jump_model(container::MultiOptimizationContainer) =
    get_jump_model(container.main_problem)
get_metadata(container::MultiOptimizationContainer) = container.metadata
get_optimizer_stats(container::MultiOptimizationContainer) = container.optimizer_stats
get_parameters(container::MultiOptimizationContainer) = container.parameters
get_resolution(container::MultiOptimizationContainer) = container.resolution
get_settings(container::MultiOptimizationContainer) = container.settings
get_time_steps(container::MultiOptimizationContainer) = container.time_steps
get_variables(container::MultiOptimizationContainer) = container.variables

set_initial_conditions_data!(container::MultiOptimizationContainer, data) =
    container.initial_conditions_data = data
get_objective_expression(container::MultiOptimizationContainer) =
    container.objective_function
is_synchronized(container::MultiOptimizationContainer) =
    container.objective_function.synchronized
set_time_steps!(container::MultiOptimizationContainer, time_steps::UnitRange{Int64}) =
    container.time_steps = time_steps

get_aux_variables(container::MultiOptimizationContainer) = container.aux_variables
get_base_power(container::MultiOptimizationContainer) = container.base_power
get_constraints(container::MultiOptimizationContainer) = container.constraints

function get_subproblem(container::MultiOptimizationContainer, id::String)
    return container.subproblems[id]
end

function check_optimization_container(container::MultiOptimizationContainer)
    for subproblem in values(container.subproblems)
        check_optimization_container(subproblem)
    end
    check_optimization_container(container.main_problem)
    return
end

function _finalize_jump_model!(
    container::MultiOptimizationContainer,
    settings::Settings,
)
    @debug "Instantiating the JuMP model" _group = LOG_GROUP_OPTIMIZATION_CONTAINER
    _finalize_jump_model!(container.main_problem, settings)
    return
end

function init_optimization_container!(
    container::MultiOptimizationContainer,
    network_model::NetworkModel{<:PM.AbstractPowerModel},
    sys::PSY.System,
)
    PSY.set_units_base_system!(sys, "SYSTEM_BASE")
    # The order of operations matter
    settings = get_settings(container)

    if get_initial_time(settings) == UNSET_INI_TIME
        if get_default_time_series_type(container) <: PSY.AbstractDeterministic
            set_initial_time!(settings, PSY.get_forecast_initial_timestamp(sys))
        elseif get_default_time_series_type(container) <: PSY.SingleTimeSeries
            ini_time, _ = PSY.check_time_series_consistency(sys, PSY.SingleTimeSeries)
            set_initial_time!(settings, ini_time)
        else
            error("Bug: unhandled $(get_default_time_series_type(container))")
        end
    end

    # TODO: what if the time series type is SingleTimeSeries?
    if get_horizon(settings) == UNSET_HORIZON
        set_horizon!(settings, PSY.get_forecast_horizon(sys))
    end
    container.time_steps = 1:get_horizon(settings)

    stats = get_optimizer_stats(container)
    stats.detailed_stats = get_detailed_optimizer_stats(settings)

    # need a special method for the main problem to initialize the optimization container
    # without actually caring about the subnetworks
    # init_optimization_container!(subproblem, network_model, sys)

    for (index, subproblem) in container.subproblems
        @debug "Initializing Container Subproblem $index" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        subproblem.settings = deepcopy(settings)
        init_optimization_container!(subproblem, network_model, sys)
        subproblem.built_for_recurrent_solves = true
    end
    _finalize_jump_model!(container, settings)
    return
end

function serialize_optimization_model(
    container::MultiOptimizationContainer,
    save_path::String,
) end
