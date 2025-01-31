#! format: off
get_variable_upper_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_maximum_capacity(d)
get_variable_lower_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_minimum_required_capacity(d)
get_variable_binary(::BuildCapacity, d::PSIP.SupplyTechnology, ::ContinuousInvestment) = false

get_variable_upper_bound(::EFCRenewable, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_maximum_capacity(d)
get_variable_lower_bound(::EFCRenewable, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_minimum_required_capacity(d)
get_variable_binary(::EFCRenewable, d::PSIP.SupplyTechnology, ::ContinuousInvestment) = false

get_variable_lower_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_multiplier(::ActivePowerVariable, ::Type{PSIP.SupplyTechnology{PSY.ThermalStandard}}) = 1.0

#! format: on

function get_default_time_series_names(::Type{U}) where {U<:PSIP.SupplyTechnology}
    return "ops_variable_cap_factor"
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U<:PSIP.SupplyTechnology,
    V<:InvestmentTechnologyFormulation,
    W<:OperationsTechnologyFormulation,
    X<:FeasibilityTechnologyFormulation,
}
    return Dict{String,Any}(
        "capacity_credit" => false
    )
end

################### Variables ####################

function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    devices::U,
    formulation::V,
    tech_model::String,
) where {
    T<:InvestmentVariableType,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:IntegerInvestment,
} where {D<:PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    binary = false

    names = [PSIP.get_name(d) for d in devices]
    check_duplicate_names(names, container, variable_type, D)

    variable = add_variable_container!(
        container,
        variable_type,
        D,
        names,
        time_steps,
        meta=tech_model,
    )
    for t in time_steps, d in devices
        name = PSY.get_name(d)
        variable[name, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "$(T)_$(D)_{$(name), $(t)}",
            integer = true,
        )
        ub = get_variable_upper_bound(variable_type, d, formulation)
        ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        lb = get_variable_lower_bound(variable_type, d, formulation)
        lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

################## Expressions ###################

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
    tech_model::String,
) where {
    T<:CumulativeCapacity,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ContinuousInvestment,
} where {D<:PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    binary = false

    var = get_variable(container, BuildCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            #binary = binary
        )
        #ub = get_variable_upper_bound(expression_type, d, formulation)
        #ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        #lb = get_variable_lower_bound(expression_type, d, formulation)
        #lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
    tech_model::String,
) where {
    T<:CumulativeCapacity,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:IntegerInvestment,
} where {D<:PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    binary = false

    var = get_variable(container, BuildCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    for t in time_steps, d in devices
        unit_size = PSIP.get_unit_size(d)
        name = PSIP.get_name(d)
        init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] * unit_size for t_p in time_steps if t_p <= t),
            #binary = binary
        )
        #ub = get_variable_upper_bound(expression_type, d, formulation)
        #ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        #lb = get_variable_lower_bound(expression_type, d, formulation)
        #lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::AbstractTechnologyFormulation,
    tech_model::String,
) where {
    T<:VariableOMCost,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
} where {D<:PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    binary = false

    var = get_variable(container, BuildCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{V},
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:SingleRegionBalanceModel,
} where {D<:PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_operational_time_steps(time_mapping)

    variable = get_variable(container, ActivePowerVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        _add_to_jump_expression!(
            expression["SingleRegion", t],
            variable[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
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
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:MultiRegionBalanceModel,
} where {D<:PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_operational_time_steps(time_mapping)

    variable = get_variable(container, ActivePowerVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        region = PSIP.get_region(d)
        _add_to_jump_expression!(
            expression[region, t],
            variable[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
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
) where {
    T<:CapacitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:SingleRegionBalanceModel,
} where {D<:PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    feasibility_indexes = get_feasibility_indexes(time_mapping)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices
        name = PSIP.get_name(d)
        power_systems_type = PSIP.get_power_systems_type(d)
        for (op_ix, feas_ix) in zip(operational_indexes, feasibility_indexes)
            time_slices = consecutive_slices[feas_ix]
            time_step_inv = inverse_invest_mapping[feas_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            ts_data = TimeSeries.values(time_series.data)
            if power_systems_type == "ThermalStandard"
                for t in time_slices
                    _add_to_jump_expression!(
                        expression["SingleRegion", t],
                        installed_cap[name, time_step_inv],
                        1.0, #get_variable_multiplier(U(), V, W()),
                    )
                end
            else
                for (ix, t) in enumerate(time_slices)
                    _add_to_jump_expression!(
                        expression["SingleRegion", t],
                        ts_data[ix] * installed_cap[name, time_step_inv],
                        1.0, #get_variable_multiplier(U(), V, W()),
                    )
                end
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
) where {
    T<:CapacitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:MultiRegionBalanceModel,
} where {D<:PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    feasibility_indexes = get_feasibility_indexes(time_mapping)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices
        name = PSIP.get_name(d)
        region = PSIP.get_region(d)
        power_systems_type = PSIP.get_power_systems_type(d)
        for (op_ix, feas_ix) in zip(operational_indexes, feasibility_indexes)
            time_slices = consecutive_slices[feas_ix]
            time_step_inv = inverse_invest_mapping[feas_ix]

            if power_systems_type == "ThermalStandard"
                for t in time_slices
                    _add_to_jump_expression!(
                        expression[region, t],
                        installed_cap[name, time_step_inv],
                        1.0, #get_variable_multiplier(U(), V, W()),
                    )
                end
            else
                time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
                ts_data = TimeSeries.values(time_series.data)
                for (ix, t) in enumerate(time_slices)
                    _add_to_jump_expression!(
                        expression[region, t],
                        ts_data[ix] * installed_cap[name, time_step_inv],
                        1.0, #get_variable_multiplier(U(), V, W()),
                    )
                end
            end
        end
    end

    return
end
################### Constraints ##################

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:ActivePowerLimitsConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActivePowerVariable,
} where {D<:PSIP.SupplyTechnology{PSY.RenewableDispatch}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)
    active_power = get_variable(container, V(), D, tech_model)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            ts_data = TimeSeries.values(time_series.data)
            first_tstamp = time_stamps[first(time_slices)]
            first_ts_tstamp = first(TimeSeries.timestamp(time_series.data))
            if first_tstamp != first_ts_tstamp
                @error(
                    "Initial timestamp of timeseries $(IS.get_name(time_series)) of technology $name does not match with the expected representative day $op_ix"
                )
            end
            time_step_inv = inverse_invest_mapping[op_ix]
            for (ix, t) in enumerate(time_slices)
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] <=
                    ts_data[ix] * installed_cap[name, time_step_inv]
                )
            end
        end
    end
    return
end

#Essentially the same constraint as above, just removed the variable capacity factor since not needed
#for thermal gen
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:ActivePowerLimitsConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActivePowerVariable,
} where {D<:PSIP.SupplyTechnology{PSY.ThermalStandard}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    device_names = PSIP.get_name.(devices)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)
    active_power = get_variable(container, V(), D, tech_model)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] <= installed_cap[name, time_step_inv]
                )
            end
        end
    end
    return
end

# Maximum cumulative capacity
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:MaximumCumulativeCapacity,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:CumulativeCapacity,
} where {D<:PSIP.SupplyTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)

    for d in devices
        name = PSIP.get_name(d)
        max_capacity = PSIP.get_maximum_capacity(d)
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity
            )
        end
    end
end


### Capacity Credit Constraint 1d
function add_constraints!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:CapacityCreditConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:BuildCapacity,
} where {D<:PSIP.SupplyTechnology{PSY.RenewableDispatch}}
    time_mapping = get_time_mapping(container)
    regions = PSIP.get_regions(PSIP.Zone, p)
    installed_cap = get_variable(container, V(), D, tech_model)
    pv_cap = 0.0
    wind_cap = 0.0
    # efc_wind = JuMP.@variable(get_jump_model(container), [1:length(regions)], lower_bound = 0, base_name = "efc_wind")
    # efc_pv = JuMP.@variable(get_jump_model(container), [1:length(regions)], lower_bound = 0, base_name = "efc_pv")
    efc = get_variable(container, EFCRenewable(), D, tech_model)
    for (r_idx, r) in enumerate(regions)
        efc_pv = 0.0
        efc_wind = 0.0
        if haskey(PSIP.get_ext(r), "pv_cc")
            for d in devices
                name = PSIP.get_name(d)
                zone = PSIP.get_region(d)
                pm = PSIP.get_prime_mover_type(d)
                if zone == r && pm == PSY.PrimeMovers.PVe
                    pv_cap = pv_cap + installed_cap[name, 1]
                    efc_pv = efc_pv + efc[name, 1]
                end
            end
            pv_cc = PSIP.get_ext(r)["pv_cc"]
            slope = pv_cc[:, 1]
            intercept = pv_cc[:, 2]

            for s in 1:length(slope)
                JuMP.@constraint(
                    get_jump_model(container),
                    efc_pv <= pv_cap * slope[s] + intercept[s]
                )
            end
        end
        if haskey(PSIP.get_ext(r), "wind_cc")
            for d in devices
                name = PSIP.get_name(d)
                zone = PSIP.get_region(d)
                pm = PSIP.get_prime_mover_type(d)
                if zone == r && pm == PSY.PrimeMovers.WT
                    wind_cap = wind_cap + installed_cap[name, 1]
                    efc_wind = efc_wind + efc[name, 1]
                end
            end
            wind_cc = PSIP.get_ext(r)["wind_cc"]
            slope = wind_cc[:, 1]
            intercept = wind_cc[:, 2]
            for s in 1:length(slope)
                JuMP.@constraint(
                    get_jump_model(container),
                    efc_wind <= pv_cap * slope[s] + intercept[s]
                )
            end
        end
    end

    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:CapacityCreditConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:BuildCapacity,
} where {D<:PSIP.SupplyTechnology{PSY.ThermalStandard}}

    return
end

########################### Objective Function Calls#############################################
# These functions are custom implementations of the cost data. In the file objective_functions.jl there are default implementations. Define these only if needed.

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Union{Vector{T},IS.FlattenIteratorWrapper{T}},
    #DeviceModel{T, U},
    formulation::BasicDispatch, #Type{<:PM.AbstractPowerModel},
    tech_model::String,
) where {T<:PSIP.SupplyTechnology}#, U <: ActivePowerVariable}
    add_variable_cost!(container, ActivePowerVariable(), devices, formulation, tech_model) #U()
    #add_start_up_cost!(container, StartVariable(), devices, U())
    #add_shut_down_cost!(container, StopVariable(), devices, U())
    #add_proportional_cost!(container, OnVariable(), devices, U())
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Union{Vector{T},IS.FlattenIteratorWrapper{T}},
    #DeviceModel{T, U},
    formulation::InvestmentTechnologyFormulation, #Type{<:PM.AbstractPowerModel},
    tech_model::String,
) where {T<:PSIP.SupplyTechnology}#, U <: BuildCapacity}
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model) #U()
    add_fixed_om_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    return
end
function objective_function!(
    container::SingleOptimizationContainer,
    devices::Union{Vector{T},IS.FlattenIteratorWrapper{T}},
    #DeviceModel{T, U},
    formulation::InvestmentTechnologyFormulation, #Type{<:PM.AbstractPowerModel},
    tech_model::String,
) where {T<:PSIP.SupplyTechnology{PSIP.RenewableDispatch}}#, U <: BuildCapacity}
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model) #U()
    #TODO: Add fixed_om costs for renewables (RenewableGenerationCost does not have fixed cost component?)
    return
end
