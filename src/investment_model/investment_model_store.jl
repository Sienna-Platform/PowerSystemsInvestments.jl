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