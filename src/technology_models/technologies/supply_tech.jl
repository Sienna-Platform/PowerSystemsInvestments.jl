#! format: off
get_variable_upper_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_capacity_limits(d).max
get_variable_lower_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_capacity_limits(d).min
get_variable_upper_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::BinaryInvestment) = nothing
get_variable_lower_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::BinaryInvestment) = 0.0
get_variable_binary(::BuildCapacity, d::PSIP.SupplyTechnology, ::ContinuousInvestment) = false

get_variable_lower_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_multiplier(_, ::Type{<:PSIP.SupplyTechnology}, ::AbstractTechnologyFormulation) = 1.0
get_expression_multiplier(_, ::Type{<:PSIP.SupplyTechnology}, ::AbstractTechnologyFormulation) = 1.0

get_init_cap(d::PSIP.SupplyTechnology, ::CumulativeCapacity, p::PSIP.Portfolio) = PSIP.get_existing_capacity_mw(p, d)

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
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

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
        init_cap = get_init_cap(d, T(), portfolio)
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
    T <: CumulativeCapacity,
    U <: Vector{D},
    V <: IntegerInvestment,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

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
        init_cap = get_init_cap(d, T(), portfolio)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] * unit_size for t_p in time_steps if t_p <= t),
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
    T <: CumulativeCapacity,
    U <: Vector{D},
    V <: BinaryInvestment,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

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
        init_cap = get_init_cap(d, T(), portfolio)
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
) where {
    T <: VariableOMCost,
    U <: Vector{D},
    V <: AbstractTechnologyFormulation,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
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

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: BasicDispatch,
    T <: EnergyBalance,
    U <: Vector{D},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    W = ActivePowerVariable
    variable = get_variable(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
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
    S <: BasicDispatch,
    T <: EnergyBalance,
    U <: Vector{D},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    W = ActivePowerVariable
    variable = get_variable(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        # Only 1 region supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
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
    S <: BasicDispatch,
    T <: EnergyBalance,
    U <: Vector{D},
    V <: NodalBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    W = ActivePowerVariable
    variable = get_variable(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        # Get each node the technology is assigned to
        for node in PSIP.get_region(d)
            node_name = PSIP.get_name(node)
            _add_to_jump_expression!(
                expression[node_name, t],
                variable[name, t],
                get_variable_multiplier(W(), D, S()),
            )
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
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    tech_model = string(S)

    W = CumulativeCapacity
    installed_cap = get_expression(container, W(), D, tech_model)
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
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    tech_model = string(S)

    W = CumulativeCapacity
    installed_cap = get_expression(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    feasibility_indexes = get_feasibility_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices
        name = PSIP.get_name(d)
        # Only 1 region supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
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

# Limits for renewables #
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
} where {D <: PSIP.SupplyTechnology{PSY.RenewableDispatch}}
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
    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    time_stamps = get_time_stamps(time_mapping)

    # DEBUG: Show time mapping structure
    if length(operational_indexes) > 12
        @warn "Time mapping has $(length(operational_indexes)) operational indexes (expected 12)"
    end

    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        tech_model = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            first_t = first(time_slices)
            first_ts = get_time_stamps(time_mapping)[first_t]
            year_actual = Dates.year(first_ts)
            month_actual = Dates.month(first_ts)
            # retrieve_ops_time_series extracts month from timestamp, so pass op_ix
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

    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        tech_model = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
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

# Limits for hydro #
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
} where {D <: PSIP.SupplyTechnology{PSY.HydroDispatch}}
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
    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        tech_model = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
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
    formulation::S,
) where {
    T <: MaximumCumulativeCapacity,
    S <: BinaryInvestment,
    U <: Vector{D},
    V <: CumulativeCapacity,
} where {D <: PSIP.SupplyTechnology}
    # For BinaryInvestment, the equality constraint BuildCapacity = binary * max_capacity
    # already enforces the capacity limit, so this constraint is not needed
    return
end

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
        max_capacity = PSIP.get_capacity_limits(d).max
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
) where {T <: PSIP.SupplyTechnology, S <: BasicDispatch}
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
    add_fixed_om_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    return
end
function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::B,
) where {
    T <: PSIP.SupplyTechnology{PSIP.RenewableDispatch},
    B <: InvestmentTechnologyFormulation,
}
    tech_model = string(B)
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    #TODO: Add fixed_om costs for renewables (RenewableGenerationCost does not have fixed cost component?)
    # add_fixed_om_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    return
end

#################### Planned Addition Constraint ####################

function add_constraints!(
    container::SingleOptimizationContainer,
    ::PlannedAdditionConstraint,
    ::CumulativeCapacity,
    devices::Vector{T},
    formulation::InvestmentTechnologyFormulation,
) where {T <: PSIP.SupplyTechnology}
    """
    Enforce that cumulative built capacity meets planned additions from time series.
    If a technology has a 'planned_addition' time series, the cumulative capacity
    at each time period must be >= the planned addition value.
    """
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(formulation)

    cumulative_cap = get_expression(container, CumulativeCapacity(), T, tech_model)

    # First pass: identify devices with planned_addition time series
    devices_with_planned_addition = String[]
    device_capacities = Dict{String, Float64}()

    for device in devices
        dev_name = PSIP.get_name(device)

        try
            # Use PSIP API to get time series from the device
            ts_list = collect(IS.get_time_series_multiple(device))

            # Look for planned_addition time series
            for ts in ts_list
                if IS.get_name(ts) == "planned_addition"
                    # Aggregate all planned_addition time series values
                    all_ts_values = Float64[]

                    for ts_check in ts_list
                        if IS.get_name(ts_check) == "planned_addition"
                            try
                                # Try standard method first
                                if hasmethod(IS.get_time_series_values, Tuple{typeof(ts_check)})
                                    ts_array = IS.get_time_series_values(ts_check)
                                elseif hasfield(typeof(ts_check), :data)
                                    # Extract values from TimeArray
                                    ts_data = getproperty(ts_check, :data)
                                    if hasmethod(values, Tuple{typeof(ts_data)})
                                        ts_array = TimeSeries.values(ts_data)
                                    else
                                        ts_array = ts_data.values
                                    end
                                else
                                    continue
                                end
                                append!(all_ts_values, vec(ts_array))
                            catch
                                continue
                            end
                        end
                    end

                    if !isempty(all_ts_values)
                        planned_capacity = maximum(all_ts_values)
                        if planned_capacity > 0.01
                            push!(devices_with_planned_addition, dev_name)
                            device_capacities[dev_name] = planned_capacity
                        end
                    end
                    break
                end
            end
        catch
            # Device doesn't have planned_addition time series, skip
            continue
        end
    end

    # Only create constraint container for devices with planned_addition
    if !isempty(devices_with_planned_addition)
        con = add_constraints_container!(
            container,
            PlannedAdditionConstraint(),
            T,
            devices_with_planned_addition,
            time_steps,
            meta=tech_model,
        )

        # Get BuildCapacity variables for exogenous units
        var = get_variable(container, BuildCapacity(), T, tech_model)

        # Add constraints only for devices with planned_addition
        for dev_name in devices_with_planned_addition
            planned_capacity = device_capacities[dev_name]

            # For exogenous units with planned_addition: require cumulative >= planned_capacity
            # Also limit to at most 1 build total (across all periods) for binary investment
            if contains(tech_model, "BinaryInvestment")
                # Constraint: sum of BuildCapacity across all periods <= 1
                # This ensures only 1 unit is built total
                build_sum_expr = sum(var[dev_name, t] for t in time_steps)
                JuMP.@constraint(
                    get_jump_model(container),
                    build_sum_expr <= 1,
                )
            end

            # Only apply constraint to the final period
            # This ensures the unit is built by the end of the planning horizon
            # (without requiring it earlier, which would be infeasible if availability is later)
            final_period = time_steps[end]
            con[dev_name, final_period] = JuMP.@constraint(
                get_jump_model(container),
                cumulative_cap[dev_name, final_period] >= planned_capacity,
            )
        end
    end

    return
end
