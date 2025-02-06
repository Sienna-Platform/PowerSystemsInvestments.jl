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

get_variable_lower_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_lower_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_lower_bound(::EnergyVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::EnergyVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_multiplier(::ActiveInPowerVariable, ::Type{PSIP.StorageTechnology}) = 1.0
get_variable_multiplier(::ActiveOutPowerVariable, ::Type{PSIP.StorageTechnology}) = 1.0

get_expression_multiplier(::EnergyBalance, ::ActiveOutPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 1.0
get_expression_multiplier(::EnergyBalance, ::ActiveInPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = -1.0
get_expression_multiplier(::FeasibilitySurplus, ::ActiveOutPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 1.0
get_expression_multiplier(::FeasibilitySurplus, ::ActiveInPowerVariable, ::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = -1.0

get_max_cap(d::PSIP.StorageTechnology, ::CumulativePowerCapacity) = PSIP.get_max_capacity_power(d)
get_max_cap(d::PSIP.StorageTechnology, ::CumulativeEnergyCapacity) = PSIP.get_max_capacity_energy(d)

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
function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    devices::U,
    formulation::V,
    tech_model::String,
) where {
    T <: InvestmentVariableType,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: IntegerInvestment,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

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
    formulation::AbstractTechnologyFormulation,
    tech_model::String,
) where {
    T <: CumulativePowerCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

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
        init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
        )
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
    T <: CumulativeEnergyCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

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
        init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
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
    tech_model::String,
) where {
    T <: CumulativeEnergyCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: IntegerInvestment,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

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

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
    tech_model::String,
) where {
    T <: CumulativePowerCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: IntegerInvestment,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

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
        unit_size = PSIP.get_unit_size_power(d)
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
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    S <: BasicDispatch,
    T <: EnergyBalance,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable}, 
    W <: SingleRegionBalanceModel,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

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
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    S <: BasicDispatch,
    T <: EnergyBalance,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable}, 
    W <: MultiRegionBalanceModel,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        zone = PSIP.get_region(d)
        _add_to_jump_expression!(
            expression[zone, t],
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
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    W <: SingleRegionBalanceModel,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

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
    formulation::BasicDispatchFeasibility,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
    W <: MultiRegionBalanceModel,
} where {D <: PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        zone = PSIP.get_region(d)
        _add_to_jump_expression!(
            expression[zone, t],
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
    tech_model::String,
) where {
    T <: Union{OutputActivePowerVariableLimitsConstraint, InputActivePowerVariableLimitsConstraint},
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: Union{ActiveOutPowerVariable, ActiveInPowerVariable},
} where {D <: PSIP.StorageTechnology}
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

    installed_cap = get_expression(container, CumulativePowerCapacity(), D, tech_model)
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
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T <: StateofChargeLimitsConstraint,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: EnergyVariable,
} where {D <: PSIP.StorageTechnology}
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

    installed_cap = get_expression(container, CumulativeEnergyCapacity(), D, tech_model)
    energy_var = get_variable(container, V(), D, tech_model)
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
    tech_model::String,
) where {
    T <: EnergyBalanceConstraint,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: EnergyVariable,
} where {D <: PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
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

    # TODO: Decide methodology for storage in different representative days
    # TODO: Current approach uses that all time steps are chronologically connected (even in different years and representative days)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        efficiency_in = PSIP.get_efficiency_in(d)
        efficiency_out = PSIP.get_efficiency_out(d)
        # TODO: Figure out what to do with initial storage
        init_storage = 0.0
        # TODO: Figure out how to store representative day time step duration
        fraction_of_hour = 1.0
        if t == 1            
            con_soc[name, t] = JuMP.@constraint(
                get_jump_model(container),
                storage_state[name, t] == init_storage + (efficiency_in * charge[name, t] - discharge[name, t] / efficiency_out) * fraction_of_hour
            )
        else
            con_soc[name, t] = JuMP.@constraint(
                get_jump_model(container),
                storage_state[name, t] ==
                storage_state[name, t - 1] + (efficiency_in * charge[name, t] - discharge[name, t] / efficiency_out) * fraction_of_hour
            )
        end
    end
end

# Maximum cumulative capacity
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T <: Union{MaximumCumulativePowerCapacity, MaximumCumulativeEnergyCapacity},
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: Union{CumulativePowerCapacity, CumulativeEnergyCapacity},
} where {D <: PSIP.StorageTechnology}
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
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    formulation::BasicDispatch,
    tech_model::String,
) where {T <: PSIP.StorageTechnology}
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
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    formulation::InvestmentTechnologyFormulation,
    tech_model::String,
) where {T <: PSIP.StorageTechnology}
    add_capital_cost!(container, BuildEnergyCapacity(), devices, formulation, tech_model)
    add_capital_cost!(container, BuildPowerCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(container, BuildEnergyCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(container, BuildPowerCapacity(), devices, formulation, tech_model)
    return
end
