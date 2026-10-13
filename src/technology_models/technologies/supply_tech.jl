#! format: off
_supported_investment_formulations(::Type{<:PSIP.SupplyTechnology}) = (ContinuousInvestment, IntegerInvestment, BinaryInvestment)

# Variables are non-negative and unbounded above unless stated otherwise
get_variable_lower_bound(::VariableType, d::PSIP.SupplyTechnology, ::AbstractTechnologyFormulation) = 0.0
get_variable_upper_bound(::VariableType, d::PSIP.SupplyTechnology, ::AbstractTechnologyFormulation) = nothing
get_variable_upper_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_capacity_limits(d).max
get_variable_lower_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_capacity_limits(d).min
# Discrete investments count units, so the limits in MW do not apply to the variable
get_variable_upper_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::Union{IntegerInvestment, BinaryInvestment}) = nothing
get_variable_lower_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::Union{IntegerInvestment, BinaryInvestment}) = 0.0

get_variable_multiplier(_, ::Type{<:PSIP.SupplyTechnology}, ::AbstractTechnologyFormulation) = 1.0
get_expression_multiplier(_, ::Type{<:PSIP.SupplyTechnology}, ::AbstractTechnologyFormulation) = 1.0

# Capacity (MW) added by one unit of the build variable
get_variable_multiplier(::BuildCapacity, d::PSIP.SupplyTechnology, ::Union{IntegerInvestment, BinaryInvestment}) = PSIP.get_unit_size(d)

#! format: on

function get_default_time_series_names(::Type{U}) where {U <: PSIP.SupplyTechnology}
    # TODO: We need to discuss about an API for timeseries names for users
    return "ops_variable_cap_factor"
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U <: PSIP.SupplyTechnology,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
    X <: FeasibilityTechnologyFormulation,
}
    return Dict{String, Any}()
end

################### Variables ####################

################## Expressions ###################

function add_expression!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: CumulativeCapacity,
    U <: Vector{D},
    V <: ContinuousInvestment,
} where {D <: PSIP.SupplyTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

    var = get_variable(container, BuildCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        get_variable_names(devices),
        time_steps,
        meta=tech_model,
    )

    for d in devices
        init_cap = PSIP.get_existing_capacity_mw(portfolio, d)
        check_multi_region_technology(d, init_cap)
        for name in get_variable_names(d)
            running = JuMP.AffExpr(init_cap)
            for t in time_steps
                JuMP.add_to_expression!(running, var[name, t])
                expression[name, t] = copy(running)
            end
        end
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: CumulativeCapacity,
    U <: Vector{D},
    V <: Union{IntegerInvestment, BinaryInvestment},
} where {D <: PSIP.SupplyTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

    var = get_variable(container, BuildCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        get_variable_names(devices),
        time_steps,
        meta=tech_model,
    )

    for d in devices
        unit_size = get_unit_size(BuildCapacity(), d, V())
        init_cap = PSIP.get_existing_capacity_mw(portfolio, d)
        check_multi_region_technology(d, init_cap)
        for name in get_variable_names(d)
            running = JuMP.AffExpr(init_cap)
            for t in time_steps
                JuMP.add_to_expression!(running, var[name, t], unit_size)
                expression[name, t] = copy(running)
            end
        end
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: VariableOMCost,
    U <: Vector{D},
    V <: AbstractTechnologyFormulation,
} where {D <: PSIP.SupplyTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(V)

    add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    return
end

# Weighted (representative-day) energy generation per operational index. Created
# for every supply technology regardless of whether any requirement uses it.
function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
) where {
    T <: WeightedEnergyGeneration,
    U <: Vector{D},
    S <: Union{BasicDispatch, BasicDispatchWithBudget, ThermalCommitmentFormulation},
} where {D <: PSIP.SupplyTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    tech_model = string(S)

    W = ActivePowerVariable
    variable = get_variable(container, W(), D, tech_model)
    mult = get_variable_multiplier(W(), D, S())

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        get_variable_names(devices),
        operational_indexes,
        meta=tech_model,
    )

    for d in devices, name in get_variable_names(d)
        for op_ix in operational_indexes
            weight = get_time_step_weight(container, op_ix)
            expression[name, op_ix] = JuMP.@expression(
                get_jump_model(container),
                weight * mult * sum(variable[name, t] for t in consecutive_slices[op_ix])
            )
        end
    end

    return
end

# Fuel consumption per time step of the technologies with a fuel curve. The container for
# their fuel cost is created with it, and is filled when the costs are added to the objective.
function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
) where {
    T <: FuelConsumptionExpression,
    U <: Vector{D},
    S <: OperationsTechnologyFormulation,
} where {D <: PSIP.SupplyTechnology}
    fuel_devices = filter(has_fuel_curve, devices)
    if isempty(fuel_devices)
        return
    end
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, ActivePowerVariable(), D, tech_model)
    expression = add_expression_container!(
        container,
        expression_type,
        D,
        get_variable_names(fuel_devices),
        time_steps,
        meta=tech_model,
    )
    add_expression_container!(
        container,
        FuelCost(),
        D,
        PSIP.get_name.(fuel_devices),
        time_steps,
        meta=tech_model,
    )

    for d in fuel_devices
        heat_rate = get_heat_rate(PSY.get_variable(PSIP.get_operation_costs(d)))
        for op_ix in get_all_indexes(time_mapping)
            fuel_per_mw = heat_rate * get_time_step_length(time_mapping, op_ix)
            for name in get_variable_names(d), t in consecutive_slices[op_ix]
                JuMP.add_to_expression!(expression[name, t], fuel_per_mw, variable[name, t])
            end
        end
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: Union{BasicDispatch, BasicDispatchWithBudget, ThermalCommitmentFormulation},
    T <: EnergyBalance,
    U <: Vector{D},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    W = ActivePowerVariable
    variable = get_variable(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, name in get_variable_names(d), t in time_steps
        _add_to_jump_expression!(
            expression[SINGLE_REGION, t],
            variable[name, t],
            get_variable_multiplier(W(), D, S()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: Union{BasicDispatch, BasicDispatchWithBudget, ThermalCommitmentFormulation},
    T <: EnergyBalance,
    U <: Vector{D},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    W = ActivePowerVariable
    variable = get_variable(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, (name, region) in get_variable_names_and_regions(d), t in time_steps
        _add_to_jump_expression!(
            expression[region, t],
            variable[name, t],
            get_variable_multiplier(W(), D, S()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: Union{BasicDispatch, BasicDispatchWithBudget, ThermalCommitmentFormulation},
    T <: EnergyBalance,
    U <: Vector{D},
    V <: NodalBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    W = ActivePowerVariable
    variable = get_variable(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices,
        (name, node_name) in get_variable_names_and_regions(d),
        t in time_steps

        _add_to_jump_expression!(
            expression[node_name, t],
            variable[name, t],
            get_variable_multiplier(W(), D, S()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    tech_model = string(S)

    W = CumulativeCapacity
    installed_cap = get_expression(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    feasibility_indexes = get_feasibility_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices, name in get_variable_names(d)
        for op_ix in feasibility_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                _add_to_jump_expression!(
                    expression[SINGLE_REGION, t],
                    installed_cap[name, time_step_inv],
                    get_expression_multiplier(W(), D, S()),
                )
            end
        end
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    tech_model = string(S)

    W = CumulativeCapacity
    installed_cap = get_expression(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    feasibility_indexes = get_feasibility_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices, (name, region) in get_variable_names_and_regions(d)
        for op_ix in feasibility_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                _add_to_jump_expression!(
                    expression[region, t],
                    installed_cap[name, time_step_inv],
                    get_expression_multiplier(W(), D, S()),
                )
            end
        end
    end

    return
end
################### Constraints ##################

# Limits for technologies with ops_variable_cap_factor time series #
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Vector{D},
    V <: ActivePowerVariable,
    S <: BasicDispatch,
    X <: TechnologyModel,
} where {
    D <: Union{
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSIP.SupplyTechnology{PSY.HydroDispatch},
    },
}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    device_names = get_variable_names(devices)
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
    time_stamps = get_time_stamps(time_mapping)

    for (ix, d) in enumerate(devices)
        tech_model = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for name in get_variable_names(d), op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            ts_data = TimeSeries.values(time_series.data)
            check_initial_timestamp(time_series, d, time_stamps[first(time_slices)], op_ix)
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

# Limits for thermals #
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Vector{D},
    V <: ActivePowerVariable,
    S <: BasicDispatch,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.ThermalStandard}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    device_names = get_variable_names(devices)
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

    for (ix, d) in enumerate(devices)
        tech_model = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for name in get_variable_names(d), op_ix in operational_indexes
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

# Dispatch is limited by the committed capacity
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Vector{D},
    V <: ActivePowerVariable,
    S <: ContinuousThermalCommitment,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.ThermalStandard}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        get_variable_names(devices),
        time_steps,
        meta=tech_model,
    )
    active_power = get_variable(container, V(), D, tech_model)
    committed_cap = get_variable(container, CommittedCapacityVariable(), D, tech_model)

    for name in get_variable_names(devices), t in time_steps
        # TODO: add lower bound for the minimum dispatch value from PSIP
        con_ub[name, t] = JuMP.@constraint(
            get_jump_model(container),
            active_power[name, t] <= committed_cap[name, t]
        )
    end
    return
end

# Committed capacity is limited by the installed capacity that is not on outage
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: CommittedCapacityLimitConstraint,
    U <: Vector{D},
    V <: CommittedCapacityVariable,
    S <: ContinuousThermalCommitment,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.ThermalStandard}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        get_variable_names(devices),
        time_steps,
        meta=tech_model,
    )
    committed_cap = get_variable(container, V(), D, tech_model)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for (ix, d) in enumerate(devices)
        outage_factors = PSIP.get_outage_factors(d)
        availability = (1.0 - outage_factors.forced) * (1.0 - outage_factors.planned)
        inv_model = string(get_investment_formulation(tech_model_vector[ix]))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for name in get_variable_names(d), op_ix in get_all_indexes(time_mapping)
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in consecutive_slices[op_ix]
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    committed_cap[name, t] <=
                    availability * installed_cap[name, time_step_inv]
                )
            end
        end
    end
    return
end

# Capacity started up within the minimum up time must still be committed. Representative
# periods are cyclic, so the time steps before the first one are the last ones of the period.
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: MinimumUpTimeConstraint,
    U <: Vector{D},
    V <: CommittedCapacityVariable,
    S <: ContinuousThermalCommitment,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.ThermalStandard}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    con_up = add_constraints_container!(
        container,
        T(),
        D,
        get_variable_names(devices),
        time_steps,
        meta=tech_model,
    )
    committed_cap = get_variable(container, V(), D, tech_model)
    start_up_cap = get_variable(container, StartUpCapacityVariable(), D, tech_model)
    consecutive_slices = get_consecutive_slices(time_mapping)

    for d in devices
        min_up_time = PSIP.get_time_limits(d).up
        for name in get_variable_names(d), op_ix in get_all_indexes(time_mapping)
            num_time_steps = get_time_steps_in_duration(time_mapping, op_ix, min_up_time)
            for t in consecutive_slices[op_ix]
                con_up[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    committed_cap[name, t] >= sum(
                        start_up_cap[
                            name,
                            get_previous_time_step(time_mapping, op_ix, t, i),
                        ] for i in 0:(num_time_steps - 1)
                    )
                )
            end
        end
    end
    return
end

# Capacity shut down within the minimum down time cannot be committed
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: MinimumDownTimeConstraint,
    U <: Vector{D},
    V <: CommittedCapacityVariable,
    S <: ContinuousThermalCommitment,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.ThermalStandard}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    con_down = add_constraints_container!(
        container,
        T(),
        D,
        get_variable_names(devices),
        time_steps,
        meta=tech_model,
    )
    committed_cap = get_variable(container, V(), D, tech_model)
    shut_down_cap = get_variable(container, ShutDownCapacityVariable(), D, tech_model)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for (ix, d) in enumerate(devices)
        min_down_time = PSIP.get_time_limits(d).down
        inv_model = string(get_investment_formulation(tech_model_vector[ix]))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for name in get_variable_names(d), op_ix in get_all_indexes(time_mapping)
            time_step_inv = inverse_invest_mapping[op_ix]
            num_time_steps = get_time_steps_in_duration(time_mapping, op_ix, min_down_time)
            for t in consecutive_slices[op_ix]
                con_down[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    committed_cap[name, t] <=
                    installed_cap[name, time_step_inv] - sum(
                        shut_down_cap[
                            name,
                            get_previous_time_step(time_mapping, op_ix, t, i),
                        ] for i in 0:(num_time_steps - 1)
                    )
                )
            end
        end
    end
    return
end

# Capacity that stays committed can change its output by the ramp limit. Capacity that starts
# up or shuts down in the time step is not limited.
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: RampRateConstraint,
    U <: Vector{D},
    V <: ActivePowerVariable,
    S <: ContinuousThermalCommitment,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.ThermalStandard}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    con_up = add_constraints_container!(
        container,
        T(),
        D,
        get_variable_names(devices),
        time_steps,
        meta="$(tech_model)_up",
    )
    con_down = add_constraints_container!(
        container,
        T(),
        D,
        get_variable_names(devices),
        time_steps,
        meta="$(tech_model)_dn",
    )
    active_power = get_variable(container, V(), D, tech_model)
    committed_cap = get_variable(container, CommittedCapacityVariable(), D, tech_model)
    start_up_cap = get_variable(container, StartUpCapacityVariable(), D, tech_model)
    shut_down_cap = get_variable(container, ShutDownCapacityVariable(), D, tech_model)
    consecutive_slices = get_consecutive_slices(time_mapping)

    for d in devices
        # Ramp limits are a fraction of the capacity per hour
        ramp_limits = PSIP.get_ramp_limits(d)
        for name in get_variable_names(d), op_ix in get_all_indexes(time_mapping)
            time_step_length = get_time_step_length(time_mapping, op_ix)
            ramp_up = min(1.0, ramp_limits.up * time_step_length)
            ramp_down = min(1.0, ramp_limits.down * time_step_length)
            for t in consecutive_slices[op_ix]
                previous_t = get_previous_time_step(time_mapping, op_ix, t)
                con_up[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] - active_power[name, previous_t] <=
                    ramp_up * (committed_cap[name, t] - start_up_cap[name, t]) +
                    start_up_cap[name, t]
                )
                con_down[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, previous_t] - active_power[name, t] <=
                    ramp_down * (committed_cap[name, t] - start_up_cap[name, t]) +
                    shut_down_cap[name, t]
                )
            end
        end
    end
    return
end

# Committed capacity changes with the capacity that starts up and shuts down
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: CommittedCapacityTrackingConstraint,
    U <: Vector{D},
    V <: CommittedCapacityVariable,
    S <: ContinuousThermalCommitment,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.ThermalStandard}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    con_tracking = add_constraints_container!(
        container,
        T(),
        D,
        get_variable_names(devices),
        time_steps,
        meta=tech_model,
    )
    committed_cap = get_variable(container, V(), D, tech_model)
    start_up_cap = get_variable(container, StartUpCapacityVariable(), D, tech_model)
    shut_down_cap = get_variable(container, ShutDownCapacityVariable(), D, tech_model)
    consecutive_slices = get_consecutive_slices(time_mapping)

    for name in get_variable_names(devices), op_ix in get_all_indexes(time_mapping)
        for t in consecutive_slices[op_ix]
            previous_t = get_previous_time_step(time_mapping, op_ix, t)
            con_tracking[name, t] = JuMP.@constraint(
                get_jump_model(container),
                committed_cap[name, t] ==
                committed_cap[name, previous_t] + start_up_cap[name, t] -
                shut_down_cap[name, t]
            )
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
    formulation::S,
) where {
    T <: MaximumCumulativeCapacity,
    S <: InvestmentTechnologyFormulation,
    U <: Vector{D},
    V <: CumulativeCapacity,
} where {D <: PSIP.SupplyTechnology}
    time_mapping = get_time_mapping(container)
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

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)

    for d in devices
        name = PSIP.get_name(d)
        # The limit applies to the total capacity over all the regions of the technology.
        variable_names = get_variable_names(d)
        max_capacity = PSIP.get_capacity_limits(d).max
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                sum(installed_cap[variable_name, t] for variable_name in variable_names) <= max_capacity
            )
        end
    end
    return
end

########################### Objective Function Calls#############################################
# These functions are custom implementations of the cost data. In the file objective_functions.jl there are default implementations. Define these only if needed.

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::S,
) where {
    T <: PSIP.SupplyTechnology,
    S <: Union{BasicDispatch, BasicDispatchWithBudget, ThermalCommitmentFormulation},
}
    tech_model = string(S)
    add_variable_cost!(container, ActivePowerVariable(), devices, formulation, tech_model)
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::B,
) where {T <: PSIP.SupplyTechnology, B <: InvestmentTechnologyFormulation}
    tech_model = string(B)
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(container, CumulativeCapacity(), devices, formulation, tech_model)
    return
end
function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::B,
) where {
    T <: PSIP.SupplyTechnology{PSY.RenewableDispatch},
    B <: InvestmentTechnologyFormulation,
}
    tech_model = string(B)
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(container, CumulativeCapacity(), devices, formulation, tech_model)
    return
end

# ActivePowerLimitsConstraint for HydroDispatch + BasicDispatchWithBudget
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Vector{D},
    V <: ActivePowerVariable,
    S <: BasicDispatchWithBudget,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.HydroDispatch}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    device_names = get_variable_names(devices)
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

    for (ix, d) in enumerate(devices)
        tech_model_d = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model_d))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for name in get_variable_names(d), op_ix in operational_indexes
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

# HydroEnergyBudgetConstraint for HydroDispatch + BasicDispatchWithBudget
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: HydroEnergyBudgetConstraint,
    U <: Vector{D},
    V <: ActivePowerVariable,
    S <: BasicDispatchWithBudget,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.HydroDispatch}}
    time_mapping = get_time_mapping(container)
    tech_model = string(S)
    device_names = get_variable_names(devices)
    operational_indexes = get_all_indexes(time_mapping)

    con_budget = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        collect(operational_indexes),
        meta=tech_model,
    )

    active_power = get_variable(container, V(), D, tech_model)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for (ix, d) in enumerate(devices)
        tech_model_d = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model_d))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for name in get_variable_names(d), op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            budget_ts = retrieve_ops_time_series(d, op_ix, time_mapping, "ops_hydro_budget")
            budget_vals = TimeSeries.values(budget_ts.data)
            total_budget_fraction = sum(budget_vals)
            con_budget[name, op_ix] = JuMP.@constraint(
                get_jump_model(container),
                sum(active_power[name, t] for t in time_slices) <=
                installed_cap[name, time_step_inv] * total_budget_fraction
            )
        end
    end
    return
end
