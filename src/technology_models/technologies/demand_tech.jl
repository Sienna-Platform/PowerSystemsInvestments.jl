function get_default_time_series_names(::Type{U}) where {U<:PSIP.DemandRequirement}
    return "ops_peak_load"
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U<:PSIP.DemandRequirement,
    V<:InvestmentTechnologyFormulation,
    W<:OperationsTechnologyFormulation,
    X<:FeasibilityTechnologyFormulation,
}
    return Dict{String,Any}(
        "planning_reserve_margin" => false
    )
end

################### Variables ####################

get_variable_multiplier(::ActivePowerVariable, ::Type{PSIP.DemandRequirement}) = -1.0

################## Expressions ###################

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{V},
    #tech_model::String,
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:SingleRegionBalanceModel,
} where {D<:PSIP.DemandRequirement}
    #@assert !isempty(devices)
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
                _add_to_jump_expression!(expression["SingleRegion", t], -1.0 * ts_data[ix])
            end
        end
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{V},
    #tech_model::String,
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:MultiRegionBalanceModel,
} where {D<:PSIP.DemandRequirement}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    expression = get_expression(container, T(), PSIP.Portfolio)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        region = PSIP.get_region(d)
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
    tech_model::String,
    transport_model::TransportModel{V},
    #tech_model::String,
) where {
    T<:CapacitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:SingleRegionBalanceModel,
} where {D<:PSIP.DemandRequirement}
    #@assert !isempty(devices)
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
                _add_to_jump_expression!(expression["SingleRegion", t], -1.0 * ts_data[ix])
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
    tech_model::String,
    transport_model::TransportModel{V},
    #tech_model::String,
) where {
    T<:CapacitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:MultiRegionBalanceModel,
} where {D<:PSIP.DemandRequirement}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    feasibility_indexes = get_feasibility_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    expression = get_expression(container, T(), PSIP.Portfolio)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        region = PSIP.get_region(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[feasibility_indexes[op_ix]]
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

### Planning Reserve Margin Constraint ####
function add_constraints!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::T,
    devices::U,
    tech_model::String,
) where {
    T<:PlanningReserveMarginConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
} where {D<:PSIP.DemandRequirement}
    time_mapping = get_time_mapping(container)
    regions = PSIP.get_regions(PSIP.Zone, p)
    efc_re = get_variable(container, EFCRenewable(), PSIP.SupplyTechnology{PSY.RenewableDispatch}, "ContinuousInvestmentBasicDispatchBasicDispatchFeasibility")
    efc_bess = get_variable(container, EFCStorage(), PSIP.StorageTechnology{PSY.EnergyReservoirStorage}, "ContinuousInvestmentSparseChrononDispatchBasicDispatchFeasibility")

    efc_thermal = get_variable(container, BuildCapacity(), PSIP.SupplyTechnology{PSY.ThermalStandard}, "IntegerInvestmentBasicDispatchBasicDispatchFeasibility")

    # efc_wind = [v for v in JuMP.all_variables(get_jump_model(container)) if occursin("efc_wind", JuMP.name(v))]
    # efc_pv = [v for v in JuMP.all_variables(get_jump_model(container)) if occursin("efc_pv", JuMP.name(v))]
    # efc_bess = [v for v in JuMP.all_variables(get_jump_model(container)) if occursin("efc_storage", JuMP.name(v))]

    re_names = axes(efc_re, 1)
    bess_names = axes(efc_bess, 1)
    th_names = axes(efc_thermal, 1)
    renewables = [PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p, n) for n in re_names]
    thermals = [PSIP.get_technology(PSIP.SupplyTechnology{PSY.ThermalStandard}, p, n) for n in th_names]
    bess = [PSIP.get_technology(PSIP.StorageTechnology{PSY.EnergyReservoirStorage}, p, n) for n in bess_names]
    efc_renewable = 0.0
    efc_storage = 0.0
    efc_th = 0.0
    for re in renewables
        name = PSIP.get_name(re)
        efc_renewable = efc_renewable + efc_re[name, 1]
    end

    for th in thermals
        name = PSIP.get_name(th)
        unit_size = PSIP.get_unit_size(th)
        outage_rate = PSIP.get_outage_factor(th)
        efc_th = efc_th + outage_rate * efc_thermal[name, 1] * unit_size
    end


    for be in bess
        name = PSIP.get_name(be)
        efc_storage = efc_storage + efc_bess[name, 1]
    end
    efc_existing = 0.0
    peak_load = 0.0
    pmr = 0.0
    for (r_idx, r) in enumerate(regions)
        efc_existing = efc_existing + PSIP.get_ext(r)["existing_efc"]
        peak_load = peak_load + PSIP.get_ext(r)["peakload"]
        pmr = PSIP.get_ext(r)["pmr"]
    end
    println(pmr * peak_load - efc_existing)
    JuMP.@constraint(
        get_jump_model(container),
        efc_th + efc_storage + efc_renewable >= pmr * peak_load - efc_existing
        # efc_storage + efc_renewable >= 100.0
    )
    return
end

### Planning Reserve Margin Constraint ####
function add_constraints!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::T,
    devices::U,
    tech_model::String,
) where {
    T<:CCNDSurfaceConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
} where {D<:PSIP.DemandRequirement}
    time_mapping = get_time_mapping(container)
    regions = PSIP.get_regions(PSIP.Zone, p)
    efc_re = get_variable(container, EFCRenewable(), PSIP.SupplyTechnology{PSY.RenewableDispatch}, "ContinuousInvestmentBasicDispatchBasicDispatchFeasibility")
    efc_bess = get_variable(container, EFCStorage(), PSIP.StorageTechnology{PSY.EnergyReservoirStorage}, "ContinuousInvestmentSparseChrononDispatchBasicDispatchFeasibility")
    bess_installed_cap = get_variable(container, BuildPowerCapacity(), PSIP.StorageTechnology{PSY.EnergyReservoirStorage}, "ContinuousInvestmentSparseChrononDispatchBasicDispatchFeasibility")
    re_installed_cap = get_variable(container, BuildCapacity(), PSIP.SupplyTechnology{PSY.RenewableDispatch}, "ContinuousInvestmentBasicDispatchBasicDispatchFeasibility")
    re_names = axes(efc_re, 1)
    bess_names = axes(efc_bess, 1)

    renewables = [PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p, n) for n in re_names]
    bess = [PSIP.get_technology(PSIP.StorageTechnology{PSY.EnergyReservoirStorage}, p, n) for n in bess_names]
    efc_pv = 0.0
    efc_wind = 0.0
    efc_storage = 0.0
    efc_phs = 0.0
    pv_cap = 0.0
    bess_cap = 0.0
    wind_cap = 0.0
    phs_cap = 0.0
    for re in renewables
        name = PSIP.get_name(re)
        if PSIP.get_prime_mover_type(re) == PSY.PrimeMovers.PVe
            efc_pv = efc_pv + efc_re[name, 1]
            pv_cap = pv_cap + re_installed_cap[name, 1]
        end
        if PSIP.get_prime_mover_type(re) == PSY.PrimeMovers.WT
            efc_wind = efc_wind + efc_re[name, 1]
            wind_cap = wind_cap + re_installed_cap[name, 1]
        end
    end


    for be in bess
        name = PSIP.get_name(be)
        if PSIP.get_storage_tech(be) == PSY.StorageTech.LIB
            efc_storage = efc_storage + efc_bess[name, 1]
            bess_cap = bess_cap + bess_installed_cap[name, 1]
        end
        if PSIP.get_storage_tech(be) ==  PSY.StorageTech.OTHER_MECH
            efc_phs =  efc_phs + efc_bess[name,1]
            phs_cap = phs_cap + bess_installed_cap[name, 1]
        end
    end

    planes = PSIP.get_ext(collect(regions)[1])["planes"]

    for p in planes
        JuMP.@constraint(
            get_jump_model(container),
            efc_phs+efc_storage + efc_pv + efc_wind <= p[1] * pv_cap + p[2] * bess_cap + p[3] * wind_cap + p[4] * phs_cap + p[5]
            # efc_storage + efc_renewable >= 100.0
        )
    end
    return
end