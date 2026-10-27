#! format: off

get_variable_upper_bound(::BuildInvestmentVariableType, d::PSIP.ColocatedSupplyStorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildInvestmentVariableType, d::PSIP.ColocatedSupplyStorageTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_binary(::BuildInvestmentVariableType, d::PSIP.ColocatedSupplyStorageTechnology, ::ContinuousInvestment) = false

get_variable_lower_bound(::ActiveInPowerVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActiveInPowerVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActiveOutPowerVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActiveOutPowerVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActivePowerSupplyVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActivePowerSupplyVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActivePowerChargeVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActivePowerChargeVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActivePowerDischargeVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActivePowerDischargeVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::StateOfChargeVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::StateOfChargeVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActiveInPowerVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActiveInPowerVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_lower_bound(::ActiveOutPowerVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActiveOutPowerVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_lower_bound(::StateOfChargeVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::StateOfChargeVariable, d::PSIP.ColocatedSupplyStorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_multiplier(::ActiveInPowerVariable, ::Type{PSIP.ColocatedSupplyStorageTechnology}) = 1.0
get_variable_multiplier(::ActiveOutPowerVariable, ::Type{PSIP.ColocatedSupplyStorageTechnology}) = 1.0

get_expression_multiplier(::EnergyBalance, ::ActiveOutPowerVariable, ::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = 1.0
get_expression_multiplier(::EnergyBalance, ::ActiveInPowerVariable, ::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = -1.0
get_expression_multiplier(::WeightedEnergyGeneration, ::ActiveOutPowerVariable, ::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = 1.0
get_expression_multiplier(::WeightedEnergyGeneration, ::ActiveInPowerVariable, ::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = -1.0
get_expression_multiplier(::FeasibilitySurplus, ::ActiveOutPowerVariable, ::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = 1.0
get_expression_multiplier(::FeasibilitySurplus, ::ActiveInPowerVariable, ::PSIP.ColocatedSupplyStorageTechnology, ::OperationsTechnologyFormulation) = -1.0

# Storage and supply data come from the technologies the co-located technology wraps
get_max_cap(d::PSIP.ColocatedSupplyStorageTechnology, ::CumulativePowerCapacity) = PSIP.get_capacity_limits_discharge(PSIP.get_storage_technology(d), IS.NU).max
get_max_cap(d::PSIP.ColocatedSupplyStorageTechnology, ::CumulativeEnergyCapacity) = PSIP.get_capacity_limits_energy(PSIP.get_storage_technology(d), IS.NU).max
get_max_cap(d::PSIP.ColocatedSupplyStorageTechnology, ::CumulativeSupplyCapacity) = PSIP.get_capacity_limits(PSIP.get_supply_technology(d), IS.NU).max
get_max_cap(d::PSIP.ColocatedSupplyStorageTechnology, ::CumulativeInverterCapacity) = PSIP.get_inverter_capacity_limits(d, IS.NU).max

get_init_cap(d::PSIP.ColocatedSupplyStorageTechnology, ::CumulativeInvestmentExpressionType, p::PSIP.Portfolio) = PSIP.get_existing_capacity_mw(p, d)

get_capital_cost_data(d::PSIP.ColocatedSupplyStorageTechnology, ::BuildPowerCapacity) = PSIP.get_discharge_capital_cost(PSIP.get_capital_costs(PSIP.get_storage_technology(d)))
get_capital_cost_data(d::PSIP.ColocatedSupplyStorageTechnology, ::BuildEnergyCapacity) = PSIP.get_energy_capital_cost(PSIP.get_capital_costs(PSIP.get_storage_technology(d)))
get_capital_cost_data(d::PSIP.ColocatedSupplyStorageTechnology, ::BuildSupplyCapacity) = PSIP.get_capital_cost(PSIP.get_capital_costs(PSIP.get_supply_technology(d)))
get_capital_cost_data(d::PSIP.ColocatedSupplyStorageTechnology, ::BuildInverterCapacity) = PSIP.get_capital_cost(PSIP.get_capital_costs_inverter(d))

get_operation_cost_data(d::PSIP.ColocatedSupplyStorageTechnology, ::Union{BuildPowerCapacity, BuildEnergyCapacity, ActivePowerChargeVariable, ActivePowerDischargeVariable}) = PSIP.get_operation_costs(PSIP.get_storage_technology(d), IS.NU)
get_operation_cost_data(d::PSIP.ColocatedSupplyStorageTechnology, ::Union{BuildSupplyCapacity, ActivePowerSupplyVariable}) = PSIP.get_operation_costs(PSIP.get_supply_technology(d), IS.NU)
get_operation_cost_data(d::PSIP.ColocatedSupplyStorageTechnology, ::BuildInverterCapacity) = PSIP.get_operation_costs_inverter(d, IS.NU)
#! format: on

function get_default_time_series_names(
    ::Type{U},
    ::ActivePowerSupplyVariable,
) where {U <: PSIP.ColocatedSupplyStorageTechnology}
    # TODO: We need to discuss about an API for timeseries names for users
    return "ops_variable_cap_factor"
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U <: PSIP.ColocatedSupplyStorageTechnology,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
    X <: FeasibilityTechnologyFormulation,
}
    return Dict{String, Any}()
end

################## Expressions ###################

function add_expression!(
    container::OptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    ::S, # variable type
    devices::U,
    formulation::V,
) where {
    T <: CumulativeInvestmentExpressionType,
    S <: BuildInvestmentVariableType,
    U <: Vector{D},
    V <: AbstractTechnologyFormulation,
} where {D <: PSIP.ColocatedSupplyStorageTechnology}
    @assert !isempty(devices)
    time_mapping = IOM.get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

    var = get_variable(container, S(), D, tech_model)

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
        init_cap = get_init_cap(d, T(), portfolio)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
        )
    end

    return
end

### Add to Expression to Energy Balance in Storage Methods ###

################### Constraints ##################

function add_constraints!(
    container::OptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
) where {
    T <: MaximumCumulativeInvestmentConstraint,
    U <: Vector{D},
    V <: CumulativeInvestmentExpressionType,
    S <: InvestmentTechnologyFormulation,
} where {D <: PSIP.ColocatedSupplyStorageTechnology}
    time_mapping = IOM.get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(S)

    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, V(), D, tech_model)

    for d in devices
        name = PSIP.get_name(d)
        max_capacity = get_max_cap(d, V())
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity
            )
        end
    end
end

# TODO: ActivePowerLimits for each type
function add_constraints!(
    container::OptimizationContainer,
    ::T,
    ::V,
    ::W,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: OperationVariableLimitsConstraintType,
    U <: Vector{D},
    V <: OperationsVariableType,
    W <: CumulativeInvestmentExpressionType,
    S <: OperationsColocatedFormulation,
    X <: TechnologyModel,
} where {D <: PSIP.ColocatedSupplyStorageTechnology}
    time_mapping = IOM.get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    active_power = get_variable(container, V(), D, tech_model)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        tech_model_d = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model_d))
        installed_cap = get_expression(container, W(), D, inv_model)
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
end

# Supply output limited by its capacity factor #
function add_constraints!(
    container::OptimizationContainer,
    ::T,
    ::V,
    ::W,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: ActivePowerSupplyVariableLimitsConstraint,
    U <: Vector{D},
    V <: ActivePowerSupplyVariable,
    W <: CumulativeSupplyCapacity,
    S <: OperationsColocatedFormulation,
    X <: TechnologyModel,
} where {D <: PSIP.ColocatedSupplyStorageTechnology}
    time_mapping = IOM.get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    active_power = get_variable(container, V(), D, tech_model)
    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    time_stamps = get_timestamps(time_mapping)

    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        tech_model = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model))
        installed_cap = get_expression(container, W(), D, inv_model)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            ts_name = get_default_time_series_names(D, V())
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping, ts_name)
            ts_data = TimeSeries.values(time_series.data)
            first_tstamp = time_stamps[first(time_slices)]
            first_ts_tstamp = IS.get_initial_timestamp(time_series)
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

function add_constraints!(
    container::OptimizationContainer,
    ::T,
    devices::U,
    formulation::S,
) where {
    T <: ColocatedInternalBalanceConstraint,
    U <: Vector{D},
    S <: OperationsColocatedFormulation,
} where {D <: PSIP.ColocatedSupplyStorageTechnology}
    time_mapping = IOM.get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    device_names = PSIP.get_name.(devices)
    con_out = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta="$(tech_model)_out",
    )
    con_in = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta="$(tech_model)_in",
    )

    active_power_out = get_variable(container, ActiveOutPowerVariable(), D, tech_model)
    active_power_in = get_variable(container, ActiveInPowerVariable(), D, tech_model)
    active_power_charge =
        get_variable(container, ActivePowerChargeVariable(), D, tech_model)
    active_power_discharge =
        get_variable(container, ActivePowerDischargeVariable(), D, tech_model)
    active_power_supply =
        get_variable(container, ActivePowerSupplyVariable(), D, tech_model)

    for d in devices
        name = PSIP.get_name(d)
        for t in time_steps
            con_out[name, t] = JuMP.@constraint(
                get_jump_model(container),
                active_power_out[name, t] ==
                active_power_discharge[name, t] + active_power_supply[name, t]
            )
            con_in[name, t] = JuMP.@constraint(
                get_jump_model(container),
                active_power_in[name, t] == active_power_charge[name, t]
            )
        end
    end
end

### Storage Balance ####
function add_constraints!(
    container::OptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
) where {
    T <: EnergyBalanceConstraint,
    U <: Vector{D},
    V <: StateOfChargeVariable,
    S <: ChronologicalColocatedDispatch,
} where {D <: PSIP.ColocatedSupplyStorageTechnology}
    time_mapping = IOM.get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    device_names = PSIP.get_name.(devices)
    con_soc = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    charge = get_variable(container, ActivePowerChargeVariable(), D, tech_model)
    discharge = get_variable(container, ActivePowerDischargeVariable(), D, tech_model)
    storage_state = get_variable(container, V(), D, tech_model)

    investment_to_operational_ixs = get_investment_map_to_operational_slices(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    time_stamps = get_timestamps(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        efficiency = PSIP.get_efficiency(PSIP.get_storage_technology(d))
        efficiency_in = efficiency.in
        efficiency_out = efficiency.out
        # For each period and first representative day, the initial storage is zero
        init_storage = 0.0
        for stage in get_investment_time_steps(time_mapping)
            stage_operational_indexes = investment_to_operational_ixs[stage]
            first_operational_index = first(stage_operational_indexes)
            for op_ix in stage_operational_indexes
                time_slices = consecutive_slices[op_ix]
                if length(time_slices) == 1
                    fraction_of_hour = 1.0
                else
                    tstamp_first = time_stamps[time_slices[1]]
                    tstamp_second = time_stamps[time_slices[2]]
                    fraction_of_hour = Dates.Hour(tstamp_second - tstamp_first).value
                end
                for (ix, t) in enumerate(time_slices)
                    # First representative day and first time point
                    if first_operational_index == op_ix && ix == 1
                        con_soc[name, t] = JuMP.@constraint(
                            get_jump_model(container),
                            storage_state[name, t] ==
                            init_storage +
                            (
                                efficiency_in * charge[name, t] -
                                discharge[name, t] / efficiency_out
                            ) * fraction_of_hour
                        )
                        # In Chronological Days, for each period/stage the state of charge is passed directly to the next representative day
                    else
                        con_soc[name, t] = JuMP.@constraint(
                            get_jump_model(container),
                            storage_state[name, t] ==
                            storage_state[name, t - 1] +
                            (
                                efficiency_in * charge[name, t] -
                                discharge[name, t] / efficiency_out
                            ) * fraction_of_hour
                        )
                    end
                end
            end
        end
    end
end

function add_constraints!(
    container::OptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
) where {
    T <: EnergyBalanceConstraint,
    U <: Vector{D},
    V <: StateOfChargeVariable,
    S <: CyclicalColocatedDispatch,
} where {D <: PSIP.ColocatedSupplyStorageTechnology}
    time_mapping = IOM.get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    device_names = PSIP.get_name.(devices)
    con_soc = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    charge = get_variable(container, ActivePowerChargeVariable(), D, tech_model)
    discharge = get_variable(container, ActivePowerDischargeVariable(), D, tech_model)
    storage_state = get_variable(container, V(), D, tech_model)

    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    time_stamps = get_timestamps(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        efficiency = PSIP.get_efficiency(PSIP.get_storage_technology(d))
        efficiency_in = efficiency.in
        efficiency_out = efficiency.out
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            if length(time_slices) == 1
                fraction_of_hour = 1.0
            else
                tstamp_first = time_stamps[time_slices[1]]
                tstamp_second = time_stamps[time_slices[2]]
                fraction_of_hour = Dates.Hour(tstamp_second - tstamp_first).value
            end
            first_time = first(time_slices)
            last_time = last(time_slices)
            for t in time_slices
                if t == first_time
                    con_soc[name, t] = JuMP.@constraint(
                        get_jump_model(container),
                        storage_state[name, t] ==
                        storage_state[name, last_time] +
                        (
                            efficiency_in * charge[name, t] -
                            discharge[name, t] / efficiency_out
                        ) * fraction_of_hour
                    )
                else
                    con_soc[name, t] = JuMP.@constraint(
                        get_jump_model(container),
                        storage_state[name, t] ==
                        storage_state[name, t - 1] +
                        (
                            efficiency_in * charge[name, t] -
                            discharge[name, t] / efficiency_out
                        ) * fraction_of_hour
                    )
                end
            end
        end
    end
end

########################### Objective Function Calls#############################################
# These functions are custom implementations of the cost data. In the file objective_functions.jl there are default implementations. Define these only if needed.

function objective_function!(
    container::OptimizationContainer,
    port::PSIP.Portfolio,
    devices::Vector{T},
    formulation::S,
) where {T <: PSIP.ColocatedSupplyStorageTechnology, S <: OperationsColocatedFormulation}
    tech_model = string(S)
    add_variable_cost!(
        container,
        port,
        ActivePowerDischargeVariable(),
        devices,
        formulation,
        tech_model,
    )
    add_variable_cost!(
        container,
        port,
        ActivePowerChargeVariable(),
        devices,
        formulation,
        tech_model,
    )
    add_variable_cost!(
        container,
        port,
        ActivePowerSupplyVariable(),
        devices,
        formulation,
        tech_model,
    )
    return
end

function objective_function!(
    container::OptimizationContainer,
    port::PSIP.Portfolio,
    devices::Vector{T},
    formulation::S,
) where {T <: PSIP.ColocatedSupplyStorageTechnology, S <: InvestmentTechnologyFormulation}
    tech_model = string(S)
    add_capital_cost!(
        container,
        port,
        BuildEnergyCapacity(),
        devices,
        formulation,
        tech_model,
    )
    add_capital_cost!(
        container,
        port,
        BuildPowerCapacity(),
        devices,
        formulation,
        tech_model,
    )
    add_capital_cost!(
        container,
        port,
        BuildSupplyCapacity(),
        devices,
        formulation,
        tech_model,
    )
    add_capital_cost!(
        container,
        port,
        BuildInverterCapacity(),
        devices,
        formulation,
        tech_model,
    )
    add_fixed_om_cost!(
        container,
        port,
        BuildEnergyCapacity(),
        devices,
        formulation,
        tech_model,
    )
    add_fixed_om_cost!(
        container,
        port,
        BuildPowerCapacity(),
        devices,
        formulation,
        tech_model,
    )
    add_fixed_om_cost!(
        container,
        port,
        BuildSupplyCapacity(),
        devices,
        formulation,
        tech_model,
    )
    add_fixed_om_cost!(
        container,
        port,
        BuildInverterCapacity(),
        devices,
        formulation,
        tech_model,
    )
    return
end
