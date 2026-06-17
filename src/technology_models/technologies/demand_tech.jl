function get_default_time_series_names(::Type{U}) where {U <: PSIP.DemandRequirement}
    # TODO: We need to discuss about an API for timeseries names for users
    return "ops_demand"
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U <: PSIP.DemandRequirement,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
    X <: FeasibilityTechnologyFormulation,
}
    return Dict{String, Any}()
end

################### Variables ####################

get_variable_multiplier(::ActivePowerVariable, ::Type{PSIP.DemandRequirement}) = -1.0

################## Expressions ###################

function add_to_expression!(
    container::OptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
    transport_model::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Vector{D},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.DemandRequirement}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    expression = get_expression(container, T(), PSIP.Portfolio)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            # Load Data is in MW
            ts_data = TimeSeries.values(time_series.data)
            first_tstamp = time_stamps[first(time_slices)]
            first_ts_tstamp = first(TimeSeries.timestamp(time_series.data))
            if first_tstamp != first_ts_tstamp
                @error(
                    "Initial timestamp of timeseries $(IS.get_name(time_series)) of technology $(d.name) does not match with the expected representative day $op_ix"
                )
            end
            for (ix, t) in enumerate(time_slices)
                _add_to_jump_expression!(expression[SINGLE_REGION, t], -1.0 * ts_data[ix])
            end
        end
    end

    return
end

function add_to_expression!(
    container::OptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
    transport_model::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Vector{D},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.DemandRequirement}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    expression = get_expression(container, T(), PSIP.Portfolio)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        # Only 1 region supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            # Load Data is in MW
            ts_data = TimeSeries.values(time_series.data)
            first_tstamp = time_stamps[first(time_slices)]
            first_ts_tstamp = first(TimeSeries.timestamp(time_series.data))
            if first_tstamp != first_ts_tstamp
                @error(
                    "Initial timestamp of timeseries $(IS.get_name(time_series)) of technology $(d.name) does not match with the expected representative day $op_ix"
                )
            end
            for (ix, t) in enumerate(time_slices)
                _add_to_jump_expression!(expression[region, t], -1.0 * ts_data[ix])
            end
        end
    end
    return
end

function add_to_expression!(
    container::OptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
    transport_model::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Vector{D},
    V <: NodalBalanceModel,
} where {D <: PSIP.DemandRequirement}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    expression = get_expression(container, T(), PSIP.Portfolio)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        # Only 1 region (node) supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            # Load Data is in MW
            ts_data = TimeSeries.values(time_series.data)
            first_tstamp = time_stamps[first(time_slices)]
            first_ts_tstamp = first(TimeSeries.timestamp(time_series.data))
            if first_tstamp != first_ts_tstamp
                @error(
                    "Initial timestamp of timeseries $(IS.get_name(time_series)) of technology $(d.name) does not match with the expected representative day $op_ix"
                )
            end
            for (ix, t) in enumerate(time_slices)
                _add_to_jump_expression!(expression[region, t], -1.0 * ts_data[ix])
            end
        end
    end
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatchFeasibility,
    transport_model::TransportModel{V},
) where {
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.DemandRequirement}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    expression = get_expression(container, T(), PSIP.Portfolio)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            # Load Data is in MW
            ts_data = TimeSeries.values(time_series.data)
            first_tstamp = time_stamps[first(time_slices)]
            first_ts_tstamp = first(TimeSeries.timestamp(time_series.data))
            if first_tstamp != first_ts_tstamp
                @error(
                    "Initial timestamp of timeseries $(IS.get_name(time_series)) of technology $(d.name) does not match with the expected representative day $op_ix"
                )
            end
            for (ix, t) in enumerate(time_slices)
                _add_to_jump_expression!(expression[SINGLE_REGION, t], -1.0 * ts_data[ix])
            end
        end
    end

    return
end

function add_to_expression!(
    container::OptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatchFeasibility,
    transport_model::TransportModel{V},
) where {
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.DemandRequirement}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    expression = get_expression(container, T(), PSIP.Portfolio)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        # Only one region supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            # Load Data is in MW
            ts_data = TimeSeries.values(time_series.data)
            first_tstamp = time_stamps[first(time_slices)]
            first_ts_tstamp = first(TimeSeries.timestamp(time_series.data))
            if first_tstamp != first_ts_tstamp
                @error(
                    "Initial timestamp of timeseries $(IS.get_name(time_series)) of technology $(d.name) does not match with the expected representative day $op_ix"
                )
            end
            for (ix, t) in enumerate(time_slices)
                _add_to_jump_expression!(expression[region, t], -1.0 * ts_data[ix])
            end
        end
    end
    return
end
