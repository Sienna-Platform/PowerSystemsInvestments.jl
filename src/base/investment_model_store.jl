"""
Stores results data for one InvestmentModel
"""
mutable struct InvestmentModelStore <: ISOPT.AbstractModelStore
    # All DenseAxisArrays have axes (column names, row indexes)
    duals::Dict{ConstraintKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}
    parameters::Dict{ParameterKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}
    variables::Dict{VariableKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}
    aux_variables::Dict{AuxVarKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}
    expressions::Dict{
        ExpressionKey,
        OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}},
    }
    optimizer_stats::OrderedDict{Dates.DateTime, ISOPT.OptimizerStats}
end

function InvestmentModelStore()
    return InvestmentModelStore(
        Dict{ConstraintKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}(),
        Dict{ParameterKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}(),
        Dict{VariableKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}(),
        Dict{AuxVarKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}(),
        Dict{ExpressionKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}(),
        OrderedDict{Dates.DateTime, ISOPT.OptimizerStats}(),
    )
end

struct ModelStoreParams <: IS.Optimization.AbstractModelStoreParams
    num_executions::Int
    horizon_count::Int
    interval::Dates.Millisecond
    resolution::Dates.Millisecond
    base_power::Float64
    system_uuid::Base.UUID
    container_metadata::IS.Optimization.OptimizationContainerMetadata

    function ModelStoreParams(
        num_executions::Int,
        horizon_count::Int,
        interval::Dates.Millisecond,
        resolution::Dates.Millisecond,
        base_power::Float64,
        system_uuid::Base.UUID,
        container_metadata=IS.Optimization.OptimizationContainerMetadata(),
    )
        new(
            num_executions,
            horizon_count,
            Dates.Millisecond(interval),
            Dates.Millisecond(resolution),
            base_power,
            system_uuid,
            container_metadata,
        )
    end
end

function ModelStoreParams(
    num_executions::Int,
    horizon::Dates.Millisecond,
    interval::Dates.Millisecond,
    resolution::Dates.Millisecond,
    base_power::Float64,
    system_uuid::Base.UUID,
    container_metadata=IS.Optimization.OptimizationContainerMetadata(),
)
    return ModelStoreParams(
        num_executions,
        horizon ÷ resolution,
        Dates.Millisecond(interval),
        Dates.Millisecond(resolution),
        base_power,
        system_uuid,
        container_metadata,
    )
end

get_num_executions(params::ModelStoreParams) = params.num_executions
get_horizon_count(params::ModelStoreParams) = params.horizon_count
get_interval(params::ModelStoreParams) = params.interval
get_resolution(params::ModelStoreParams) = params.resolution
get_base_power(params::ModelStoreParams) = params.base_power
get_system_uuid(params::ModelStoreParams) = params.system_uuid
deserialize_key(params::ModelStoreParams, name) =
    deserialize_key(params.container_metadata, name)

function initialize_storage!(
    store::InvestmentModelStore,
    container::ISOPT.AbstractOptimizationContainer,
    params::ModelStoreParams,
)
    num_of_executions = get_num_executions(params)
    if length(get_time_steps(container)) < 1
        error("The time step count in the optimization container is not defined")
    end
    time_steps_count = get_time_steps(container)[end]
    initial_time = get_initial_time(container)
    model_interval = get_interval(params)
    for type in STORE_CONTAINERS
        field_containers = getfield(container, type)
        results_container = getfield(store, type)
        for (key, field_container) in field_containers
            !should_write_resulting_value(key) && continue
            @debug "Adding $(encode_key_as_string(key)) to InvestmentModelStore" _group =
                LOG_GROUP_MODEL_STORE
            column_names = get_column_names(key, field_container)
            data = OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}()
            for timestamp in
                range(initial_time; step=model_interval, length=num_of_executions)
                data[timestamp] = fill!(
                    DenseAxisArray{Float64}(undef, column_names..., 1:time_steps_count),
                    NaN,
                )
            end
            results_container[key] = data
        end
    end
    return
end

struct InvestmentModelIndexType end

function write_result!(
    store::InvestmentModelStore,
    name::Symbol,
    key::OptimizationContainerKey,
    index::InvestmentModelIndexType,
    update_timestamp::Dates.DateTime,
    array::DenseAxisArray{<:Any, 2},
)
    columns = axes(array)[1]
    if eltype(columns) !== String
        # TODO: This happens because buses are stored by indexes instead of name.
        columns = string.(columns)
    end
    container = getfield(store, get_store_container_type(key))
    container[key][index] = DenseAxisArray(array.data, columns, 1:size(array)[2])
    return
end

function write_result!(
    store::InvestmentModelStore,
    name::Symbol,
    key::OptimizationContainerKey,
    index::InvestmentModelIndexType,
    update_timestamp::Dates.DateTime,
    array::DenseAxisArray{<:Any, 1},
)
    columns = axes(array)[1]
    if eltype(columns) !== String
        # TODO: This happens because buses are stored by indexes instead of name.
        columns = string.(columns)
    end
    container = getfield(store, get_store_container_type(key))
    container[key][index] =
        DenseAxisArray(reshape(array.data, 1, length(columns)), ["1"], columns)
    return
end

function read_results(
    store::InvestmentModelStore,
    key::OptimizationContainerKey;
    index::Union{InvestmentModelIndexType, Nothing}=nothing,
)
    container = getfield(store, get_store_container_type(key))
    data = container[key]
    if isnothing(index)
        @assert length(data) == 1
        index = first(keys(data))
    end

    # Return a copy because callers may mutate it.
    return deepcopy(data[index])
end

function write_optimizer_stats!(
    store::InvestmentModelStore,
    stats::ISOPT.OptimizerStats,
    index::InvestmentModelIndexType,
)
    if index in keys(store.optimizer_stats)
        @warn "Overwriting optimizer stats"
    end
    store.optimizer_stats[index] = stats
    return
end

function read_optimizer_stats(store::InvestmentModelStore)
    stats = [to_namedtuple(x) for x in values(store.optimizer_stats)]
    df = DataFrames.DataFrame(stats)
    DataFrames.insertcols!(df, 1, :DateTime => keys(store.optimizer_stats))
    return df
end

function get_column_names(store::InvestmentModelStore, key::OptimizationContainerKey)
    container = getfield(store, get_store_container_type(key))
    return get_column_names(key, first(values(container[key])))
end
