#! format: off
get_variable_upper_bound(::BuildCapacity, d::PSIP.AggregateTransportTechnology, ::InvestmentTechnologyFormulation) = get_max_new_capacity(d)
get_variable_lower_bound(::BuildCapacity, d::PSIP.AggregateTransportTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_binary(::BuildCapacity, d::PSIP.AggregateTransportTechnology, ::ContinuousInvestment) = false
get_variable_upper_bound(::BuildCapacity, d::PSIP.AggregateTransportTechnology, ::BinaryInvestment) = nothing
get_variable_lower_bound(::BuildCapacity, d::PSIP.AggregateTransportTechnology, ::BinaryInvestment) = 0.0

get_variable_upper_bound(::BuildCapacity, d::PSIP.NodalACTransportTechnology, ::InvestmentTechnologyFormulation) = get_max_new_capacity(d)
get_variable_lower_bound(::BuildCapacity, d::PSIP.NodalACTransportTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_binary(::BuildCapacity, d::PSIP.NodalACTransportTechnology, ::ContinuousInvestment) = false
get_variable_upper_bound(::BuildCapacity, d::PSIP.NodalACTransportTechnology, ::BinaryInvestment) = nothing
get_variable_lower_bound(::BuildCapacity, d::PSIP.NodalACTransportTechnology, ::BinaryInvestment) = 0.0

get_variable_lower_bound(::FlowActivePowerVariable, d::PSIP.AggregateTransportTechnology, ::OperationsTechnologyFormulation) = nothing
get_variable_upper_bound(::FlowActivePowerVariable, d::PSIP.AggregateTransportTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::FlowActivePowerVariable, d::PSIP.NodalACTransportTechnology, ::OperationsTechnologyFormulation) = nothing
get_variable_upper_bound(::FlowActivePowerVariable, d::PSIP.NodalACTransportTechnology, ::OperationsTechnologyFormulation) = nothing

get_max_cap(d::PSIP.TransmissionTechnology, ::CumulativeCapacity) = PSIP.get_capacity_limits(d).max
get_min_cap(d::PSIP.TransmissionTechnology, ::CumulativeCapacity) = PSIP.get_capacity_limits(d).min

get_init_cap(d::PSIP.TransmissionTechnology, ::CumulativeCapacity, p::PSIP.Portfolio) = PSIP.get_existing_capacity_mw(p, d)

#! format: on

function get_max_new_capacity(d::PSIP.AggregateTransportTechnology)
    @warn "get_existing_line_capacity is not implemented for AggregateTransportTechnology. Returning maximum limits."
    return PSIP.get_capacity_limits(d).max
end

# TODO: Check if there is a different way we can get the existing line capacity
function get_existing_line_capacity(d::PSIP.AggregateTransportTechnology)
    @warn "get_existing_line_capacity is not implemented for AggregateTransportTechnology. Returning minimum limits."
    return PSIP.get_capacity_limits(d).min
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U <: PSIP.TransmissionTechnology,
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
    formulation::S,
) where {
    T <: CumulativeCapacity,
    S <: AbstractTechnologyFormulation,
    U <: Vector{D},
} where {D <: PSIP.AggregateTransportTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(S)

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

function add_to_expression!(
    ::SingleOptimizationContainer,
    ::T,
    ::U,
    ::BasicDispatch,
    ::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Vector{D},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.AggregateTransportTechnology}
    # Do nothing for Transport Paths in SingleRegion models
    return
end

function add_to_expression!(
    ::SingleOptimizationContainer,
    ::T,
    ::U,
    ::BasicDispatch,
    ::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Vector{D},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.NodalACTransportTechnology}
    # Do nothing for Nodal Transport Paths in SingleRegion models
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    ::S,
    ::TransportModel{V},
) where {
    T <: EnergyBalance,
    S <: BasicDispatch,
    U <: Vector{D},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.AggregateTransportTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, FlowActivePowerVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    # Assuming that energy travels from start to end, so if dispatch of Branch is positive, it is subtracted from start_region
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        start_region = PSIP.get_name(PSIP.get_start_region(d))
        end_region = PSIP.get_name(PSIP.get_end_region(d))
        losses = PSIP.get_line_loss(d)
        _add_to_jump_expression!(expression[start_region, t], variable[name, t], -1.0)
        _add_to_jump_expression!(
            expression[end_region, t],
            variable[name, t],
            (1.0 - losses), # Losses are assumed in the end region
        )
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
    T <: ActivePowerLimitsConstraint,
    S <: BasicDispatch,
    U <: Vector{D},
    V <: FlowActivePowerVariable,
    X <: TechnologyModel,
} where {D <: PSIP.AggregateTransportTechnology}
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
    con_lb = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta="$(tech_model)_lb",
    )

    active_power = get_variable(container, V(), D, tech_model)
    operational_indexes = get_operational_indexes(time_mapping)
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
                con_lb[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] >= -installed_cap[name, time_step_inv]
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
    S <: ContinuousInvestment,
    U <: Vector{D},
    V <: CumulativeCapacity,
} where {D <: PSIP.AggregateTransportTechnology}
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
        max_capacity = get_max_cap(d, CumulativeCapacity())
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity
            )
        end
    end
end

# Maximum cumulative capacity for NodalACTransportTechnology
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
) where {
    T <: MaximumCumulativeCapacity,
    S <: ContinuousInvestment,
    U <: Vector{D},
    V <: CumulativeCapacity,
} where {D <: PSIP.NodalACTransportTechnology}
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
        max_capacity = get_max_cap(d, CumulativeCapacity())
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity
            )
        end
    end
end

########################### Objective Function Calls#############################################

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::S,
) where {T <: PSIP.AggregateTransportTechnology, S <: ContinuousInvestment}
    tech_model = string(S)
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    # TODO: Decide if we want to include fixed OM cost for Transport Paths
    #add_fixed_om_cost!(container, CumulativeCapacity(), devices, formulation, tech_model)
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::S,
) where {T <: PSIP.NodalACTransportTechnology, S <: ContinuousInvestment}
    tech_model = string(S)
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    return
end

########################### Nodal AC Transport Technology Methods #################################

# Investment variable bounds
get_variable_upper_bound(
    ::BuildCapacity,
    d::PSIP.NodalACTransportTechnology,
    ::InvestmentTechnologyFormulation,
) = PSIP.get_capacity_limits(d).max
get_variable_lower_bound(
    ::BuildCapacity,
    d::PSIP.NodalACTransportTechnology,
    ::InvestmentTechnologyFormulation,
) = 0.0
get_variable_binary(
    ::BuildCapacity,
    d::PSIP.NodalACTransportTechnology,
    ::ContinuousInvestment,
) = false
get_variable_binary(
    ::BuildCapacity,
    d::PSIP.NodalACTransportTechnology,
    ::BinaryInvestment,
) = true
get_variable_upper_bound(
    ::BuildCapacity,
    d::PSIP.NodalACTransportTechnology,
    ::BinaryInvestment,
) = 1.0
get_variable_lower_bound(
    ::BuildCapacity,
    d::PSIP.NodalACTransportTechnology,
    ::BinaryInvestment,
) = 0.0

# Cumulative capacity bounds
get_max_cap(d::PSIP.NodalACTransportTechnology, ::CumulativeCapacity) =
    PSIP.get_capacity_limits(d).max
get_min_cap(d::PSIP.NodalACTransportTechnology, ::CumulativeCapacity) =
    PSIP.get_capacity_limits(d).min
get_init_cap(d::PSIP.NodalACTransportTechnology, ::CumulativeCapacity, p::PSIP.Portfolio) =
    PSIP.get_existing_capacity_mw(p, d)

# Operations variable bounds: bidirectional flow with magnitude <= capacity
get_variable_lower_bound(
    ::FlowActivePowerVariable,
    d::PSIP.NodalACTransportTechnology,
    ::OperationsTechnologyFormulation,
) =
    let
        cap_max = PSIP.get_capacity_limits(d).max
        -cap_max
    end

get_variable_upper_bound(
    ::FlowActivePowerVariable,
    d::PSIP.NodalACTransportTechnology,
    ::OperationsTechnologyFormulation,
) = PSIP.get_capacity_limits(d).max

# Energy balance contribution: negative at start node, positive at end node (no losses for now)
function add_to_expression!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    ::S,
    ::TransportModel{V},
) where {
    T <: EnergyBalance,
    S <: BasicDispatch,
    U <: Vector{D},
    V <: NodalBalanceModel,
} where {D <: PSIP.NodalACTransportTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, FlowActivePowerVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        start_node = PSIP.get_name(PSIP.get_start_node(d))
        end_node = PSIP.get_name(PSIP.get_end_node(d))
        # Flow leaves start node, enters end node (no losses assumed)
        _add_to_jump_expression!(expression[start_node, t], variable[name, t], -1.0)
        _add_to_jump_expression!(expression[end_node, t], variable[name, t], 1.0)
    end

    return
end

# Constraints: |flow| <= cumulative capacity (two inequality constraints per line)
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: ActivePowerLimitsConstraint,
    S <: BasicDispatch,
    U <: Vector{D},
    V <: FlowActivePowerVariable,
    X <: TechnologyModel,
} where {D <: PSIP.NodalACTransportTechnology}
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

    # Create second constraint container for upper bounds using different constraint type
    con_ub_upper = add_constraints_container!(
        container,
        FlowActivePowerUpperBoundConstraint(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    variable = get_variable(container, FlowActivePowerVariable(), D, tech_model)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        tech_model_d = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model_d))
        installed_cap_inv = get_expression(container, CumulativeCapacity(), D, inv_model)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                # Lower bound: flow >= -capacity
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    variable[name, t] >= -installed_cap_inv[name, time_step_inv]
                )
                # Upper bound: flow <= capacity
                con_ub_upper[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    variable[name, t] <= installed_cap_inv[name, time_step_inv]
                )
            end
        end
    end
end

# ============================================================================
# NodalACTransportTechnology add_expression! methods
# ============================================================================

function add_expression!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    devices::U,
    formulation::S,
) where {
    T <: CumulativeCapacity,
    S <: AbstractTechnologyFormulation,
    U <: Vector{D},
} where {D <: PSIP.NodalACTransportTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(S)

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
