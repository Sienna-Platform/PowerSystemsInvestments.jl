"""
Function to create a unique index of time series names for each device model. For example,
if two parameters each reference the same time series name, this function will return a
different value for each parameter entry
"""
function _create_time_series_multiplier_index(
    model,
    ::Type{T},
) where {T <: TimeSeriesParameter}
    ts_names = get_time_series_names(model)
    if length(ts_names) > 1
        ts_name = ts_names[T]
        ts_id = findfirst(x -> x == T, [k for (k, v) in ts_names if v == ts_name])
    else
        ts_id = 1
    end
    return ts_id
end

function add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    devices::U,
    model, # TODO: update model def
) where {
    T <: ParameterType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractTechnologyFormulation,
} where {D <: Technology}
    if has_container_key(container, T, D)
        return
    end
    _add_parameters!(container, T(), devices, model)
    return
end

function add_parameters!(
    container::OptimizationContainer,
    ::Type{T},
    ff::AbstractAffectFeedforward,
    model, # TODO: update model def
    devices::V,
) where {
    T <: VariableValueParameter,
    V <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractTechnologyFormulation,
} where {D <: Technology}
    if has_container_key(container, T, D)
        return
    end
    source_key = get_optimization_container_key(ff)
    _add_parameters!(container, T(), source_key, model, devices)
    return
end

function _add_parameters!(
    container::OptimizationContainer,
    param::T,
    devices::U,
    model,# TODO: update model def
) where {
    T <: TimeSeriesParameter,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractTechnologyFormulation,
} where {D <: Technology}
    _add_time_series_parameters!(container, param, devices, model)
    return
end

function _add_time_series_parameters!(
    container::OptimizationContainer,
    param::T,
    devices,
    model::DeviceModel{D, W},
) where {D <: Technology, T <: TimeSeriesParameter, W <: AbstractTechnologyFormulation}
    ts_type = get_default_time_series_type(container)
    if !(ts_type <: Union{PSY.AbstractDeterministic, PSY.StaticTimeSeries})
        error("add_parameters! for TimeSeriesParameter is not compatible with $ts_type")
    end
    time_steps = get_time_steps(container)
    ts_name = get_time_series_names(model)[T]
    time_series_mult_id = _create_time_series_multiplier_index(model, T)

    # @debug "adding" T D ts_name ts_type time_series_mult_id _group =
    #     LOG_GROUP_OPTIMIZATION_CONTAINER

    device_names = String[]
    initial_values = Dict{String, AbstractArray}()
    for device in devices
        push!(device_names, PSY.get_name(device))
        ts_uuid = string(IS.get_time_series_uuid(ts_type, device, ts_name))
        if !(ts_uuid in keys(initial_values))
            initial_values[ts_uuid] =
                get_time_series_initial_values!(container, ts_type, device, ts_name)
        end
    end

    param_container = add_param_container!(
        container,
        param,
        D,
        ts_type,
        ts_name,
        collect(keys(initial_values)),
        device_names,
        time_steps,
    )
    set_time_series_multiplier_id!(get_attributes(param_container), time_series_mult_id)
    jump_model = get_jump_model(container)

    for (ts_uuid, ts_values) in initial_values
        for step in time_steps
            set_parameter!(param_container, jump_model, ts_values[step], ts_uuid, step)
        end
    end

    for device in devices
        name = PSY.get_name(device)
        multiplier = get_multiplier_value(T(), device, W())
        for step in time_steps
            set_multiplier!(param_container, multiplier, name, step)
        end
        add_component_name!(
            get_attributes(param_container),
            name,
            string(IS.get_time_series_uuid(ts_type, device, ts_name)),
        )
    end
    return
end

function _add_parameters!(
    container::OptimizationContainer,
    param::T,
    devices::U,
    model, # TODO: update model def
) where {
    T <: ObjectiveFunctionParameter,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractTechnologyFormulation,
} where {D <: Technology}
    _add_time_series_parameters!(container, param, devices, model)
    return
end

function _add_parameters!(
    container::OptimizationContainer,
    ::T,
    key::VariableKey{U, D},
    model, # TODO: update model def
    devices::V,
) where {
    T <: VariableValueParameter,
    U <: VariableType,
    V <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    W <: AbstractTechnologyFormulation,
} where {D <: Technology}
    @debug "adding" T D U _group = LOG_GROUP_OPTIMIZATION_CONTAINER
    names = [PSY.get_name(device) for device in devices]
    time_steps = get_time_steps(container)
    parameter_container = add_param_container!(container, T(), D, key, names, time_steps)
    jump_model = get_jump_model(container)
    for d in devices
        name = PSY.get_name(d)
        if get_variable_warm_start_value(U(), d, W()) === nothing
            inital_parameter_value = 0.0
        else
            inital_parameter_value = get_variable_warm_start_value(U(), d, W())
        end
        for t in time_steps
            set_multiplier!(
                parameter_container,
                get_parameter_multiplier(T(), d, W()),
                name,
                t,
            )
            set_parameter!(parameter_container, jump_model, inital_parameter_value, name, t)
        end
    end
    return
end
