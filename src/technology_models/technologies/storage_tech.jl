#! format: off

# TODO: Update when storage is updated in portfolios
get_variable_upper_bound(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_upper_bound(::BuildEnergyCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildEnergyCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_binary(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::ContinuousInvestment) = false

get_variable_lower_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::EnergyVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::EnergyVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_multiplier(::ActiveInPowerVariable, ::Type{PSIP.StorageTechnology}) = 1.0
get_variable_multiplier(::ActiveOutPowerVariable, ::Type{PSIP.StorageTechnology}) = 1.0

#! format: on

function get_default_time_series_names(
    ::Type{U},
    ::Type{V},
    ::Type{W},
) where {
    U <: PSIP.StorageTechnology,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
}
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
) where {
    U <: PSIP.StorageTechnology,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
}
    return Dict{String, Any}()
end

################### Variables ####################

################## Expressions ###################

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::AbstractTechnologyFormulation,
) where {
    T <: CumulativePowerCapacity,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_steps = get_time_steps_investments(container)
    binary = false

    var = get_variable(container, BuildPowerCapacity(), D)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
    )

    # TODO: Move to add_to_expression!
    # TODO: Update with initial capacity once portfolios are updates
    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        #init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            #init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            sum(var[name, t_p] for t_p in time_steps if t_p <= t),
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
) where {
    T <: CumulativeEnergyCapacity,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_steps = get_time_steps_investments(container)
    binary = false

    var = get_variable(container, BuildEnergyCapacity(), D)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
    )

    # TODO: Move to add_to_expression!
    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        #init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            #init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            #binary = binary
        )
        #ub = get_variable_upper_bound(expression_type, d, formulation)
        #ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        #lb = get_variable_lower_bound(expression_type, d, formulation)
        #lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
) where {
    T <: SupplyTotal,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, ActiveOutPowerVariable(), D)
    expression = get_expression(container, T(), PSIP.DemandRequirement{PSY.PowerLoad})

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[t],
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
) where {
    T <: DemandTotal,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, ActiveInPowerVariable(), D)
    expression = get_expression(container, T(), PSIP.DemandRequirement{PSY.PowerLoad})

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[t],
            variable[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
) where {
    T <: ActivePowerBalance,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    expression = get_expression(container, T)

    #TODO: move to separate add_to_expression! function, could not figure out ExpressionKey
    variable = get_variable(container, ActivePowerVariable(), D)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[t],
            variable[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

################### Constraints ##################

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
) where {
    T <: OutputActivePowerVariableLimitsConstraint,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: ActiveOutPowerVariable,
} where {D <: PSIP.StorageTechnology{PSY.EnergyReservoirStorage}}
    time_steps = get_time_steps(container)
    # Hard Code Mapping #
    # TODO: Remove
    @warn("creating hard code mapping. Remove it later")
    mapping_ops = Dict(("2030", 1) => 1:24, ("2035", 1) => 25:48)
    mapping_inv = Dict("2030" => 1, "2035" => 2)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(container, T(), D, device_names, time_steps)

    installed_cap = get_expression(container, CumulativePowerCapacity(), D)
    active_power = get_variable(container, V(), D)

    for d in devices
        name = PSIP.get_name(d)
        ts_name = "ops_variable_cap_factor"
        ts_keys = filter(x -> x.name == ts_name, IS.get_time_series_keys(d))
        for ts_key in ts_keys
            ts_type = ts_key.time_series_type
            features = ts_key.features
            year = features["year"]
            #rep_day = features["rep_day"]
            ts_data = TimeSeries.values(
                #IS.get_time_series(ts_type, d, ts_name; year=year, rep_day=rep_day).data,
                IS.get_time_series(ts_type, d, ts_name; year=year).data,
            )
            #time_steps_ix = mapping_ops[(year, rep_day)]
            time_steps_ix = mapping_ops[(year, 1)]
            time_step_inv = mapping_inv[year]
            for (ix, t) in enumerate(time_steps_ix)
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] <= installed_cap[name, time_step_inv]
                )
            end
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
) where {
    T <: InputActivePowerVariableLimitsConstraint,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: ActiveInPowerVariable,
} where {D <: PSIP.StorageTechnology{PSY.EnergyReservoirStorage}}
    time_steps = get_time_steps(container)
    # Hard Code Mapping #
    # TODO: Remove
    @warn("creating hard code mapping. Remove it later")
    mapping_ops = Dict(("2030", 1) => 1:24, ("2035", 1) => 25:48)
    mapping_inv = Dict("2030" => 1, "2035" => 2)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(container, T(), D, device_names, time_steps)

    installed_cap = get_expression(container, CumulativePowerCapacity(), D)
    active_power = get_variable(container, V(), D)

    for d in devices
        name = PSIP.get_name(d)
        ts_name = "ops_variable_cap_factor"
        ts_keys = filter(x -> x.name == ts_name, IS.get_time_series_keys(d))
        for ts_key in ts_keys
            ts_type = ts_key.time_series_type
            features = ts_key.features
            year = features["year"]
            #rep_day = features["rep_day"]
            ts_data = TimeSeries.values(
                #IS.get_time_series(ts_type, d, ts_name; year=year, rep_day=rep_day).data,
                IS.get_time_series(ts_type, d, ts_name; year=year).data,
            )
            #time_steps_ix = mapping_ops[(year, rep_day)]
            time_steps_ix = mapping_ops[(year, 1)]
            time_step_inv = mapping_inv[year]
            for (ix, t) in enumerate(time_steps_ix)
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] <= installed_cap[name, time_step_inv]
                )
            end
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
) where {
    T <: StateofChargeLimitsConstraint,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: EnergyVariable,
} where {D <: PSIP.StorageTechnology{PSY.EnergyReservoirStorage}}
    time_steps = get_time_steps(container)
    # Hard Code Mapping #
    # TODO: Remove
    @warn("creating hard code mapping. Remove it later")
    mapping_ops = Dict(("2030", 1) => 1:24, ("2035", 1) => 25:48)
    mapping_inv = Dict("2030" => 1, "2035" => 2)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(container, T(), D, device_names, time_steps)

    installed_cap = get_expression(container, CumulativeEnergyCapacity(), D)
    active_power = get_variable(container, V(), D)

    for d in devices
        name = PSIP.get_name(d)
        ts_name = "ops_variable_cap_factor"
        ts_keys = filter(x -> x.name == ts_name, IS.get_time_series_keys(d))
        for ts_key in ts_keys
            ts_type = ts_key.time_series_type
            features = ts_key.features
            year = features["year"]
            #rep_day = features["rep_day"]
            ts_data = TimeSeries.values(
                #IS.get_time_series(ts_type, d, ts_name; year=year, rep_day=rep_day).data,
                IS.get_time_series(ts_type, d, ts_name; year=year).data,
            )
            #time_steps_ix = mapping_ops[(year, rep_day)]
            time_steps_ix = mapping_ops[(year, 1)]
            time_step_inv = mapping_inv[year]
            for (ix, t) in enumerate(time_steps_ix)
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] <= installed_cap[name, time_step_inv]
                )
            end
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
) where {
    T <: EnergyBalanceConstraint,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: EnergyVariable,
} where {D <: PSIP.StorageTechnology{PSY.EnergyReservoirStorage}}
    time_steps = get_time_steps(container)
    # Hard Code Mapping #
    # TODO: Remove
    @warn("creating hard code mapping. Remove it later")
    mapping_ops = Dict(("2030", 1) => 1:24, ("2035", 1) => 25:48)
    mapping_inv = Dict("2030" => 1, "2035" => 2)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(container, T(), D, device_names, time_steps)

    charge = get_variable(container, ActiveInPowerVariable(), D)
    discharge = get_variable(container, ActiveOutPowerVariable(), D)
    storage_state = get_variable(container, V(), D)

    for d in devices
        name = PSIP.get_name(d)
        ts_name = "ops_variable_cap_factor"
        ts_keys = filter(x -> x.name == ts_name, IS.get_time_series_keys(d))
        for ts_key in ts_keys
            ts_type = ts_key.time_series_type
            features = ts_key.features
            year = features["year"]
            #rep_day = features["rep_day"]
            ts_data = TimeSeries.values(
                #IS.get_time_series(ts_type, d, ts_name; year=year, rep_day=rep_day).data,
                IS.get_time_series(ts_type, d, ts_name; year=year).data,
            )
            #time_steps_ix = mapping_ops[(year, rep_day)]
            time_steps_ix = mapping_ops[(year, 1)]
            time_step_inv = mapping_inv[year]
            for (ix, t) in enumerate(time_steps_ix)
                if ix == 1
                    con_ub[name, t] = JuMP.@constraint(
                        get_jump_model(container),
                        storage_state[name, t] == charge[name, t] - discharge[name, t]
                    )
                else
                    con_ub[name, t] = JuMP.@constraint(
                        get_jump_model(container),
                        storage_state[name, t] ==
                        storage_state[name, t - 1] + charge[name, t] - discharge[name, t]
                    )
                end
            end
        end
    end
end

# Maximum cumulative capacity
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    #::NetworkModel{X},
) where {
    T <: MaximumCumulativePowerCapacity,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: CumulativePowerCapacity,
    #X <: PM.AbstractPowerModel,
} where {D <: PSIP.StorageTechnology}
    time_steps = get_time_steps_investments(container)

    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(container, T(), D, device_names, time_steps)

    installed_cap = get_expression(container, V(), D)

    for d in devices
        name = PSIP.get_name(d)

        # TODO: Remove hard coding when StorageTechnology is updated in portfolio
        max_capacity = 100000 #PSIP.get_maximum_capacity(d)
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity
            )
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    #::NetworkModel{X},
) where {
    T <: MaximumCumulativeEnergyCapacity,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: CumulativeEnergyCapacity,
    #X <: PM.AbstractPowerModel,
} where {D <: PSIP.StorageTechnology}
    time_steps = get_time_steps_investments(container)

    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(container, T(), D, device_names, time_steps)

    installed_cap = get_expression(container, V(), D)

    for d in devices
        name = PSIP.get_name(d)
        # TODO: Remove hard coding when StorageTechnology is updated in portfolio
        max_capacity = 100000 #PSIP.get_maximum_capacity(d)
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity
            )
        end
    end
end

########################### Objective Function Calls#############################################
# These functions are custom implementations of the cost data. In the file objective_functions.jl there are default implementations. Define these only if needed.

function objective_function!(
    container::SingleOptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    #DeviceModel{T, U},
    formulation::BasicDispatch, #Type{<:PM.AbstractPowerModel},
) where {T <: PSIP.StorageTechnology}#, U <: ActivePowerVariable}
    add_variable_cost!(container, ActivePowerVariable(), devices, formulation) #U()
    #add_start_up_cost!(container, StartVariable(), devices, U())
    #add_shut_down_cost!(container, StopVariable(), devices, U())
    #add_proportional_cost!(container, OnVariable(), devices, U())
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::IS.FlattenIteratorWrapper{T},
    #DeviceModel{T, U},
    formulation::ContinuousInvestment, #Type{<:PM.AbstractPowerModel},
) where {T <: PSIP.SupplyTechnology}#, U <: BuildCapacity}
    add_capital_cost!(container, BuildCapacity(), devices, formulation) #U()
    add_fixed_om_cost!(container, CumulativeCapacity(), devices, formulation)
    return
end
