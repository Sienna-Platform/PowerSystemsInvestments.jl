#! format: off

_supported_investment_formulations(::Type{<:PSIP.StorageTechnology}) = (ContinuousInvestment, IntegerInvestment)

# Variables are non-negative and unbounded above
get_variable_lower_bound(::VariableType, d::PSIP.StorageTechnology, ::AbstractTechnologyFormulation) = 0.0
get_variable_upper_bound(::VariableType, d::PSIP.StorageTechnology, ::AbstractTechnologyFormulation) = nothing

get_variable_multiplier(::ActiveInPowerVariable, ::Type{<:PSIP.StorageTechnology}) = 1.0
get_variable_multiplier(::ActiveOutPowerVariable, ::Type{<:PSIP.StorageTechnology}) = 1.0
# Capacity added by one unit of the build variables
get_variable_multiplier(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::IntegerInvestment) = PSIP.get_unit_size_discharge(d)
get_variable_multiplier(::BuildEnergyCapacity, d::PSIP.StorageTechnology, ::IntegerInvestment) = PSIP.get_unit_size_energy(d)

get_expression_multiplier(::EnergyBalance, ::ActiveOutPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 1.0
get_expression_multiplier(::EnergyBalance, ::ActiveInPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = -1.0
get_expression_multiplier(::WeightedEnergyGeneration, ::ActiveOutPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 1.0
get_expression_multiplier(::WeightedEnergyGeneration, ::ActiveInPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = -1.0
get_expression_multiplier(::FeasibilitySurplus, ::ActiveOutPowerVariable, ::PSIP.StorageTechnology, ::FeasibilityTechnologyFormulation) = 1.0
get_expression_multiplier(::FeasibilitySurplus, ::ActiveInPowerVariable, ::PSIP.StorageTechnology, ::FeasibilityTechnologyFormulation) = -1.0

# TODO: Defaulting to using discharge values for symmetric storage, but we need to be careful if we implement asymmetric storage investments
get_max_cap(d::PSIP.StorageTechnology, ::CumulativePowerCapacity) = PSIP.get_capacity_limits_discharge(d).max
get_max_cap(d::PSIP.StorageTechnology, ::CumulativeEnergyCapacity) = PSIP.get_capacity_limits_energy(d).max

#! format: on

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U <: PSIP.StorageTechnology,
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
    T <: CumulativePowerCapacity,
    U <: Vector{D},
    V <: AbstractTechnologyFormulation,
} where {D <: PSIP.StorageTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

    var = get_variable(container, BuildPowerCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    for d in devices
        name = PSIP.get_name(d)
        init_cap = PSIP.get_existing_capacity_mw(portfolio, d)
        running = JuMP.AffExpr(init_cap)
        for t in time_steps
            JuMP.add_to_expression!(running, var[name, t])
            expression[name, t] = copy(running)
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
    T <: CumulativeEnergyCapacity,
    U <: Vector{D},
    V <: AbstractTechnologyFormulation,
} where {D <: PSIP.StorageTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

    var = get_variable(container, BuildEnergyCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    for d in devices
        name = PSIP.get_name(d)
        init_cap = PSIP.get_existing_capacity_mwh(portfolio, d)
        running = JuMP.AffExpr(init_cap)
        for t in time_steps
            JuMP.add_to_expression!(running, var[name, t])
            expression[name, t] = copy(running)
        end
    end

    return
end

# PowerCap for IntegerInvestment
function add_expression!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: CumulativePowerCapacity,
    U <: Vector{D},
    V <: IntegerInvestment,
} where {D <: PSIP.StorageTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

    var = get_variable(container, BuildPowerCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    for d in devices
        unit_size = get_unit_size(BuildPowerCapacity(), d, V())
        name = PSIP.get_name(d)
        init_cap = PSIP.get_existing_capacity_mw(portfolio, d)
        running = JuMP.AffExpr(init_cap)
        for t in time_steps
            JuMP.add_to_expression!(running, var[name, t], unit_size)
            expression[name, t] = copy(running)
        end
    end

    return
end

# EnergyCap for Integer decisions in Storage
function add_expression!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: CumulativeEnergyCapacity,
    U <: Vector{D},
    V <: IntegerInvestment,
} where {D <: PSIP.StorageTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

    var = get_variable(container, BuildEnergyCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    for d in devices
        unit_size = get_unit_size(BuildEnergyCapacity(), d, V())
        name = PSIP.get_name(d)
        init_cap = PSIP.get_existing_capacity_mwh(portfolio, d)
        running = JuMP.AffExpr(init_cap)
        for t in time_steps
            JuMP.add_to_expression!(running, var[name, t], unit_size)
            expression[name, t] = copy(running)
        end
    end

    return
end

# Weighted (representative-day) net-discharge energy per operational index for
# storage and co-located technologies. Net discharge = out - in. Created for
# every such technology regardless of whether any requirement uses it.
function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
) where {
    T <: WeightedEnergyGeneration,
    U <: Vector{D},
    S <: Union{OperationsStorageFormulation, OperationsColocatedFormulation},
} where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    tech_model = string(S)

    out_var = get_variable(container, ActiveOutPowerVariable(), D, tech_model)
    in_var = get_variable(container, ActiveInPowerVariable(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        operational_indexes,
        meta=tech_model,
    )

    for d in devices
        name = PSIP.get_name(d)
        out_mult = get_expression_multiplier(T(), ActiveOutPowerVariable(), d, S())
        in_mult = get_expression_multiplier(T(), ActiveInPowerVariable(), d, S())
        for op_ix in operational_indexes
            weight = get_time_step_weight(container, op_ix)
            expression[name, op_ix] = JuMP.@expression(
                get_jump_model(container),
                weight * sum(
                    out_mult * out_var[name, t] + in_mult * in_var[name, t] for
                    t in consecutive_slices[op_ix]
                )
            )
        end
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::S,
    transport_model::TransportModel{W},
) where {
    S <: Union{OperationsStorageFormulation, OperationsColocatedFormulation},
    T <: EnergyBalance,
    U <: Vector{D},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    W <: SingleRegionBalanceModel,
} where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        _add_to_jump_expression!(
            expression[SINGLE_REGION, t],
            variable[name, t],
            get_expression_multiplier(T(), V(), d, S()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::S,
    transport_model::TransportModel{W},
) where {
    S <: Union{OperationsStorageFormulation, OperationsColocatedFormulation},
    T <: EnergyBalance,
    U <: Vector{D},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    W <: AbstractNodalTransportAggregation,
} where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        # Only 1 region (node) supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
        _add_to_jump_expression!(
            expression[region, t],
            variable[name, t],
            get_expression_multiplier(T(), V(), d, S()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::S,
    transport_model::TransportModel{W},
) where {
    S <: Union{OperationsStorageFormulation, OperationsColocatedFormulation},
    T <: EnergyBalance,
    U <: Vector{D},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    W <: MultiRegionBalanceModel,
} where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        # Only 1 region supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
        _add_to_jump_expression!(
            expression[region, t],
            variable[name, t],
            get_expression_multiplier(T(), V(), d, S()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::S,
    transport_model::TransportModel{W},
) where {
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    W <: SingleRegionBalanceModel,
} where {D <: PSIP.StorageTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_feasibility_time_steps(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        _add_to_jump_expression!(
            expression[SINGLE_REGION, t],
            variable[name, t],
            get_expression_multiplier(T(), V(), d, S()),
        )
    end
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::S,
    transport_model::TransportModel{W},
) where {
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    W <: MultiRegionBalanceModel,
} where {D <: PSIP.StorageTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_feasibility_time_steps(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        # Only 1 region supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
        _add_to_jump_expression!(
            expression[region, t],
            variable[name, t],
            get_expression_multiplier(T(), V(), d, S()),
        )
    end
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::S,
    transport_model::TransportModel{W},
) where {
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    W <: AbstractNodalTransportAggregation,
} where {D <: PSIP.StorageTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_feasibility_time_steps(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        # Only 1 region (node) supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
        _add_to_jump_expression!(
            expression[region, t],
            variable[name, t],
            get_expression_multiplier(T(), V(), d, S()),
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
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: Union{
        OutputActivePowerVariableLimitsConstraint,
        InputActivePowerVariableLimitsConstraint,
    },
    U <: Vector{D},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    S <: OperationsStorageFormulation,
    X <: TechnologyModel,
} where {D <: PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
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
        installed_cap = get_expression(container, CumulativePowerCapacity(), D, inv_model)
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

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: StateOfChargeLimitsConstraint,
    U <: Vector{D},
    V <: StateOfChargeVariable,
    S <: OperationsStorageFormulation,
    X <: TechnologyModel,
} where {D <: PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
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

    energy_var = get_variable(container, V(), D, tech_model)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        tech_model_d = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model_d))
        installed_cap = get_expression(container, CumulativeEnergyCapacity(), D, inv_model)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    energy_var[name, t] <= installed_cap[name, time_step_inv]
                )
            end
        end
    end
    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
) where {
    T <: EnergyBalanceConstraint,
    U <: Vector{D},
    V <: StateOfChargeVariable,
    S <: ChronologicalStorageDispatch,
} where {D <: PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
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

    charge = get_variable(container, ActiveInPowerVariable(), D, tech_model)
    discharge = get_variable(container, ActiveOutPowerVariable(), D, tech_model)
    storage_state = get_variable(container, V(), D, tech_model)

    investment_to_operational_ixs = get_investment_map_to_operational_slices(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        efficiency_in = PSIP.get_efficiency(d).in
        efficiency_out = PSIP.get_efficiency(d).out
        # For each period and first representative day, the initial storage is zero
        init_storage = 0.0
        for stage in get_investment_time_steps(time_mapping)
            stage_operational_indexes = investment_to_operational_ixs[stage]
            first_operational_index = first(stage_operational_indexes)
            for op_ix in stage_operational_indexes
                time_slices = consecutive_slices[op_ix]
                time_step_length = get_time_step_length(time_mapping, op_ix)
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
                            ) * time_step_length
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
                            ) * time_step_length
                        )
                    end
                end
            end
        end
    end
    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
) where {
    T <: EnergyBalanceConstraint,
    U <: Vector{D},
    V <: StateOfChargeVariable,
    S <: CyclicalStorageDispatch,
} where {D <: PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
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

    charge = get_variable(container, ActiveInPowerVariable(), D, tech_model)
    discharge = get_variable(container, ActiveOutPowerVariable(), D, tech_model)
    storage_state = get_variable(container, V(), D, tech_model)

    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    time_stamps = get_time_stamps(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        efficiency_in = PSIP.get_efficiency(d).in
        efficiency_out = PSIP.get_efficiency(d).out
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_length = get_time_step_length(time_mapping, op_ix)
            for t in time_slices
                # The state of charge of the first time step follows the last one
                previous_t = get_previous_time_step(time_mapping, op_ix, t)
                con_soc[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    storage_state[name, t] ==
                    storage_state[name, previous_t] +
                    (
                        efficiency_in * charge[name, t] -
                        discharge[name, t] / efficiency_out
                    ) * time_step_length
                )
            end
        end
    end
    return
end

# Storage duration constraints
function add_constraints!(
    container::SingleOptimizationContainer,
    ::StorageDurationLowerBoundConstraint,
    devices::U,
    formulation::S,
) where {
    U <: Vector{D},
    S <: InvestmentTechnologyFormulation,
} where {D <: PSIP.StorageTechnology}
    time_steps = get_investment_time_steps(get_time_mapping(container))
    tech_model = string(S)
    device_names = PSIP.get_name.(devices)
    constraints = add_constraints_container!(
        container,
        StorageDurationLowerBoundConstraint(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )
    cumulative_power = get_expression(container, CumulativePowerCapacity(), D, tech_model)
    cumulative_energy = get_expression(container, CumulativeEnergyCapacity(), D, tech_model)

    for d in devices
        name = PSIP.get_name(d)
        minimum_duration = PSIP.get_duration_limits(d).min
        for t in time_steps
            constraints[name, t] = JuMP.@constraint(
                get_jump_model(container),
                cumulative_energy[name, t] >= minimum_duration * cumulative_power[name, t]
            )
        end
    end
    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::StorageDurationUpperBoundConstraint,
    devices::U,
    formulation::S,
) where {
    U <: Vector{D},
    S <: InvestmentTechnologyFormulation,
} where {D <: PSIP.StorageTechnology}
    time_steps = get_investment_time_steps(get_time_mapping(container))
    tech_model = string(S)
    device_names = PSIP.get_name.(devices)
    constraints = add_constraints_container!(
        container,
        StorageDurationUpperBoundConstraint(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )
    cumulative_power = get_expression(container, CumulativePowerCapacity(), D, tech_model)
    cumulative_energy = get_expression(container, CumulativeEnergyCapacity(), D, tech_model)

    for d in devices
        name = PSIP.get_name(d)
        maximum_duration = PSIP.get_duration_limits(d).max
        for t in time_steps
            constraints[name, t] = JuMP.@constraint(
                get_jump_model(container),
                cumulative_energy[name, t] <= maximum_duration * cumulative_power[name, t]
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
    T <: Union{MaximumCumulativePowerCapacity, MaximumCumulativeEnergyCapacity},
    U <: Vector{D},
    V <: Union{CumulativePowerCapacity, CumulativeEnergyCapacity},
    S <: InvestmentTechnologyFormulation,
} where {D <: PSIP.StorageTechnology}
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
    return
end

########################### Objective Function Calls#############################################
# These functions are custom implementations of the cost data. In the file objective_functions.jl there are default implementations. Define these only if needed.

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::S,
) where {T <: PSIP.StorageTechnology, S <: OperationsStorageFormulation}
    tech_model = string(S)
    add_variable_cost!(
        container,
        ActiveOutPowerVariable(),
        devices,
        formulation,
        tech_model,
    )
    add_variable_cost!(container, ActiveInPowerVariable(), devices, formulation, tech_model)
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::S,
) where {T <: PSIP.StorageTechnology, S <: InvestmentTechnologyFormulation}
    tech_model = string(S)
    add_capital_cost!(container, BuildEnergyCapacity(), devices, formulation, tech_model)
    add_capital_cost!(container, BuildPowerCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(
        container,
        CumulativePowerCapacity(),
        devices,
        formulation,
        tech_model,
    )
    return
end
