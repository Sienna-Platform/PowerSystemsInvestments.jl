#! format: off
get_variable_upper_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_max_capacity(d)
get_variable_lower_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_min_capacity(d)
get_variable_binary(::BuildCapacity, d::PSIP.SupplyTechnology, ::ContinuousInvestment) = false

get_variable_lower_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_multiplier(::ActivePowerVariable, ::Type{PSIP.SupplyTechnology{PSY.ThermalStandard}}) = 1.0

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
} where {D <: PSIP.SupplyTechnology}
    #@assert !isempty(devices)
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
    formulation::V,
    tech_model::String,
) where {
    T <: CumulativeCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: ContinuousInvestment,
} where {D <: PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

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
    T <: CumulativeCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: IntegerInvestment,
} where {D <: PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

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
    T <: VariableOMCost,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

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

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

    variable = get_variable(container, ActivePowerVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        _add_to_jump_expression!(
            expression[SINGLE_REGION, t],
            variable[name, t],
            1.0, #TODO: get_variable_multiplier methods
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
    T <: EnergyBalance,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

    variable = get_variable(container, ActivePowerVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        region = PSIP.get_region(d)
        _add_to_jump_expression!(
            expression[region, t],
            variable[name, t],
            1.0, #TODO: get_variable_multiplier methods
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
    T <: FeasibilitySurplus,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    feasibility_indexes = get_feasibility_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices
        name = PSIP.get_name(d)
        for op_ix in feasibility_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                _add_to_jump_expression!(
                    expression[SINGLE_REGION, t],
                    installed_cap[name, time_step_inv],
                    1.0, #TODO: get_variable_multiplier methods
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
    formulation::BasicDispatchFeasibility,
    tech_model::String,
    transport_model::TransportModel{V},
) where {
    T <: FeasibilitySurplus,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    # @assert !isempty(devices)
    time_mapping = get_time_mapping(container)

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    feasibility_indexes = get_feasibility_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices
        name = PSIP.get_name(d)
        region = PSIP.get_region(d)
        for op_ix in feasibility_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                _add_to_jump_expression!(
                    expression[region, t],
                    installed_cap[name, time_step_inv],
                    1.0, #TODO: get_variable_multiplier methods
                )
            end
        end
    end

    return
end
################### Constraints ##################

# Limits for renewables #
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: ActivePowerVariable,
} where {D <: PSIP.SupplyTechnology{PSY.RenewableDispatch}}
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
    operational_indexes = get_all_indexes(time_mapping)
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

# Limits for thermals #
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: ActivePowerVariable,
} where {D <: PSIP.SupplyTechnology{PSY.ThermalStandard}}
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
    operational_indexes = get_all_indexes(time_mapping)
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
    T <: MaximumCumulativeCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: CumulativeCapacity,
} where {D <: PSIP.SupplyTechnology}
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
        max_capacity = PSIP.get_max_capacity(d)
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
    formulation::BasicDispatch, #Type{<:PM.AbstractPowerModel},
    tech_model::String,
) where {T <: PSIP.SupplyTechnology}#, U <: ActivePowerVariable}
    add_variable_cost!(container, ActivePowerVariable(), devices, formulation, tech_model)
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    formulation::InvestmentTechnologyFormulation, #Type{<:PM.AbstractPowerModel},
    tech_model::String,
) where {T <: PSIP.SupplyTechnology}#, U <: BuildCapacity}
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model) #U()
    add_fixed_om_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    return
end
function objective_function!(
    container::SingleOptimizationContainer,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    formulation::InvestmentTechnologyFormulation,
    tech_model::String,
) where {T <: PSIP.SupplyTechnology{PSIP.RenewableDispatch}}#, U <: BuildCapacity}
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model) #U()
    #TODO: Add fixed_om costs for renewables (RenewableGenerationCost does not have fixed cost component?)
    return
end
