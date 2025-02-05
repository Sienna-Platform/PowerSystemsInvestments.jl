mutable struct InvestmentModelStore <: ISOPT.AbstractModelStore
    # All DenseAxisArrays have axes (column names, row indexes)
    duals::Dict{ConstraintKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}
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
        Dict{VariableKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}(),
        Dict{AuxVarKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}(),
        Dict{ExpressionKey, OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}}(),
        OrderedDict{Dates.DateTime, ISOPT.OptimizerStats}(),
    )
end

struct ModelStoreParams <: ISOPT.AbstractModelStoreParams
    base_power::Float64
    system_uuid::Base.UUID
    container_metadata::ISOPT.OptimizationContainerMetadata
end

get_base_power(params::ModelStoreParams) = params.base_power
get_system_uuid(params::ModelStoreParams) = params.system_uuid
deserialize_key(params::ModelStoreParams, name) =
    deserialize_key(params.container_metadata, name)

function initialize_storage!(
    store::InvestmentModelStore,
    container::ISOPT.AbstractOptimizationContainer,
    params::ModelStoreParams,
)
    time_mapping = get_time_mapping(container)
    if length(get_time_steps(time_mapping)) < 1
        error("The time step count in the optimization container is not defined")
    end
    base_timestamp = get_base_date(time_mapping)
    op_time_steps_count = get_total_operation_period_count(time_mapping)
    cap_time_steps_count = get_total_investment_period_count(time_mapping)
    #fes_time_steps_count = get_total_investment_period_count(time_mapping)
    for type in STORE_CONTAINERS
        field_containers = getfield(container, type)
        results_container = getfield(store, type)
        for (key, field_container) in field_containers
            !should_write_resulting_value(key) && continue
            entry_type = get_entry_type(key)
            if is_operation_entry(entry_type)
                count = op_time_steps_count
            elseif is_investment_entry(entry_type)
                count = cap_time_steps_count
            else
                error()
            end
            @debug "Adding $(encode_key_as_string(key)) to InvestmentModelStore" _group =
                LOG_GROUP_MODEL_STORE
            column_names = get_column_names(key, field_container)
            data = OrderedDict{Dates.DateTime, DenseAxisArray{Float64, 2}}()
            data[base_timestamp] =
                fill!(DenseAxisArray{Float64}(undef, column_names..., 1:count), NaN)
            results_container[key] = data
        end
    end
    return
end

function write_result!(
    store::InvestmentModelStore,
    name::Symbol,
    key::OptimizationContainerKey,
    index::Dates.Date,
    update_timestamp::Dates.Date,
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
    index::Dates.Date,
    update_timestamp::Dates.Date,
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

function read_results(store::InvestmentModelStore, key::OptimizationContainerKey;)
    container = getfield(store, get_store_container_type(key))
    data = container[key]
    # Return a copy because callers may mutate it.
    return deepcopy(data)
end

function write_optimizer_stats!(
    store::InvestmentModelStore,
    stats::ISOPT.OptimizerStats,
    index::Dates.Date,
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
