#! format: off

get_variable_upper_bound(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_upper_bound(::BuildEnergyCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildEnergyCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_binary(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::ContinuousInvestment) = false

get_variable_lower_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::StateOfChargeVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::StateOfChargeVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_lower_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_lower_bound(::StateOfChargeVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::StateOfChargeVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_multiplier(::ActiveInPowerVariable, ::Type{PSIP.StorageTechnology}) = 1.0
get_variable_multiplier(::ActiveOutPowerVariable, ::Type{PSIP.StorageTechnology}) = 1.0

get_expression_multiplier(::EnergyBalance, ::ActiveOutPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 1.0
get_expression_multiplier(::EnergyBalance, ::ActiveInPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = -1.0
get_expression_multiplier(::FeasibilitySurplus, ::ActiveOutPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 1.0
get_expression_multiplier(::FeasibilitySurplus, ::ActiveInPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = -1.0

get_max_cap(d::PSIP.StorageTechnology, ::CumulativePowerCapacity) = PSIP.get_capacity_power_limits(d).max
get_max_cap(d::PSIP.StorageTechnology, ::CumulativeEnergyCapacity) = PSIP.get_capacity_energy_limits(d).max

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

function get_existing_capacity_power(
    d::PSIP.StorageTechnology{X},
    p::PSIP.Portfolio,
) where {X <: PSY.EnergyReservoirStorage}
    try
        # pull out any ExistingCapacity attributes
        attrs = IS.get_supplemental_attributes(PSIP.ExistingCapacity, d)
    catch e
        @warn "ExistingCapacity attribute not found – returning 0.0"
        return 0.0
    end

    attrs = IS.get_supplemental_attributes(PSIP.ExistingCapacity, d)

    if length(attrs) != 1
        @warn length(attrs) > 1 ? 
            "Multiple ExistingCapacity attributes – returning 0.0" :
            "No ExistingCapacity attribute – returning 0.0"
        return 0.0
    end

    techs = attrs[1].existing_technologies
    isempty(techs) && (
        @warn "ExistingCapacity has no listed technologies – returning 0.0"; 
        return 0.0
    )

    comps = PSY.get_components(X, p.base_system)
    isempty(comps) && (
        @warn "No components of type $X in system – returning 0.0"; 
        return 0.0
    )

    # TODO: Rodrigo review whether building a Set for fast name‐membership tests is the direction we want
    tech_set = Set(techs)

    # filter out just the components whose name is declared
    matched = [c for c in comps if c.name in tech_set]

    # Check 1) if nothing matched at all, warn & exit
    if isempty(matched)
        @warn "No components matching any of $(collect(tech_set)) in the system – returning 0.0"
        return 0.0
    end

    # Check 2) if some declared names didn't correspond to any component, warn about the missing ones
    found_names = Set(c.name for c in matched)
    missing     = setdiff(tech_set, found_names)
    if !isempty(missing)
        @warn "Declared technologies not found in system components: $(collect(missing))"
    end

    # return sum up the ratings of all matched components
    return sum(PSY.get_rating(c) for c in matched)
end

function get_existing_capacity_energy(
    d::PSIP.StorageTechnology{X},
    p::PSIP.Portfolio,
) where {X <: PSY.EnergyReservoirStorage}
    try
        # TODO: Review why the ExistingCapacity attribute is not being found
        # pull out any ExistingCapacity attributes
        attrs = IS.get_supplemental_attributes(PSIP.ExistingCapacity, d)
    catch e
        @warn "ExistingCapacity attribute not found – returning 0.0"
        return 0.0
    end

    attrs = IS.get_supplemental_attributes(PSIP.ExistingCapacity, d)

    if length(attrs) != 1
        @warn length(attrs) > 1 ? 
            "Multiple ExistingCapacity attributes – returning 0.0" :
            "No ExistingCapacity attribute – returning 0.0"
        return 0.0
    end

    techs = attrs[1].existing_technologies
    isempty(techs) && (
        @warn "ExistingCapacity has no listed technologies – returning 0.0"; 
        return 0.0
    )

    comps = PSY.get_components(X, p.base_system)
    isempty(comps) && (
        @warn "No components of type $X in system – returning 0.0"; 
        return 0.0
    )

    # TODO: Rodrigo review whether building a Set for fast name‐membership tests is the direction we want
    tech_set = Set(techs)

    # filter out just the components whose name is declared
    matched = [c for c in comps if c.name in tech_set]

    # Check 1) if nothing matched at all, warn & exit
    if isempty(matched)
        @warn "No components matching any of $(collect(tech_set)) in the system – returning 0.0"
        return 0.0
    end

    # Check 2) if some declared names didn't correspond to any component, warn about the missing ones
    found_names = Set(c.name for c in matched)
    missing     = setdiff(tech_set, found_names)
    if !isempty(missing)
        @warn "Declared technologies not found in system components: $(collect(missing))"
    end

    # return sum up the ratings of all matched components
    return sum(PSY.get_storage_capacity(c) for c in matched)
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
    @assert !isempty(devices)
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

    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        init_cap = get_existing_capacity_power(d, portfolio)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
        )
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
    @assert !isempty(devices)
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

    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        init_cap = get_existing_capacity_energy(d, portfolio)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
        )
    end

    return
end

# PowerCap for IntegerInvestment
function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: CumulativePowerCapacity,
    U <: Vector{D},
    V <: IntegerInvestment,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
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

    for t in time_steps, d in devices
        unit_size = PSIP.get_unit_size_energy(d)
        name = PSIP.get_name(d)
        init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] * unit_size for t_p in time_steps if t_p <= t),
        )
    end

    return
end

# EnergyCap for Integer decisions in Storage
function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: CumulativeEnergyCapacity,
    U <: Vector{D},
    V <: IntegerInvestment,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
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

    for t in time_steps, d in devices
        unit_size = PSIP.get_unit_size_energy(d)
        name = PSIP.get_name(d)
        init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] * unit_size for t_p in time_steps if t_p <= t),
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
    W <: SingleRegionBalanceModel,
} where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    @assert !isempty(devices)
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
    W <: MultiRegionBalanceModel,
} where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    @assert !isempty(devices)
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
    @assert !isempty(devices)
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
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    W <: MultiRegionBalanceModel,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
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
    add_fixed_om_cost!(container, BuildEnergyCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(container, BuildPowerCapacity(), devices, formulation, tech_model)
    return
end
