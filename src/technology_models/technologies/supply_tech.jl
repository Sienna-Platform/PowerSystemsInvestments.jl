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
    at the final period must equal the planned addition value.
    """
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(formulation)

    # Identify devices with planned_addition time series and extract per-period values
    devices_with_planned_addition = Dict{String, Vector{Float64}}()  # device_name -> [values per period]

    for device in devices
        dev_name = PSIP.get_name(device)

        try
            # Use PSIP API to get time series from the device
            ts_list = collect(IS.get_time_series_multiple(device))

            for ts in ts_list
                if IS.get_name(ts) == "planned_addition"
                    # Extract hourly time series values and aggregate to periods by year
                    ts_values = Float64[]
                    try
                        if hasmethod(IS.get_time_series_values, Tuple{typeof(ts)})
                            ts_array = IS.get_time_series_values(ts)
                            ts_values = vec(ts_array)
                        elseif hasfield(typeof(ts), :data)
                            ts_data = getproperty(ts, :data)
                            if hasmethod(values, Tuple{typeof(ts_data)})
                                ts_values = vec(TimeSeries.values(ts_data))
                            else
                                ts_values = vec(ts_data.values)
                            end
                        end

                        # Map hourly values to periods based on year boundaries
                        # Time series covers min_year to max_year (from planning.jl)
                        if !isempty(ts_values) && length(time_steps) <= 4
                            period_values = Float64[]

                            # Simple mapping: assume time_steps correspond to rep_years
                            # (2025, 2027, 2028, 2032) → periods roughly span those years
                            # Count hours per year in the time series
                            min_year = isempty(time_steps) ? 2025 : 2025
                            hours_per_year_estimate = 8760

                            for t_idx in 1:length(time_steps)
                                # Period t covers roughly: min_year + (t-1) year(s) to min_year + t year(s)
                                # For now, use a heuristic based on time_steps
                                year_in_period = min_year + t_idx - 1

                                # Find which hours correspond to this period
                                # Hours 0-8759 = min_year, 8760-17519 = min_year+1, etc.
                                start_hour = (t_idx - 1) * 8760 * 4  # rough estimate for 4-year periods
                                end_hour = min(t_idx * 8760 * 4, length(ts_values))

                                if start_hour < end_hour && start_hour < length(ts_values)
                                    period_cap = maximum(ts_values[max(1, start_hour):min(end_hour, length(ts_values))])
                                    push!(period_values, period_cap)
                                else
                                    push!(period_values, 0.0)
                                end
                            end

                            # Store the per-period values
                            if length(period_values) == length(time_steps)
                                devices_with_planned_addition[dev_name] = period_values
                            end
                        end
                    catch
                        continue
                    end
                    break
                end
            end
        catch
            # Device doesn't have time series, skip
            continue
        end
    end

    # Add constraints only for devices with planned_addition
    if !isempty(devices_with_planned_addition)
        # Get BuildCapacity variables for exogenous units
        var = get_variable(container, BuildCapacity(), T, tech_model)

        for (dev_name, ts_values) in devices_with_planned_addition
            # Find the first period where capacity is planned (where max value > 0)
            build_period_idx = findfirst(v -> v > 0.01, ts_values)
            planned_capacity = build_period_idx !== nothing ? ts_values[build_period_idx] : 0.0

            # Exogenous units: build exactly when the time series specifies
            for (period_idx, t) in enumerate(time_steps)
                if period_idx == build_period_idx
                    # Build in the specified period
                    JuMP.@constraint(
                        get_jump_model(container),
                        var[dev_name, t] >= planned_capacity,
                    )
                else
                    # All other periods: no builds
                    JuMP.@constraint(
                        get_jump_model(container),
                        var[dev_name, t] == 0,
                    )
                end
            end
        end
    end

    return
end
