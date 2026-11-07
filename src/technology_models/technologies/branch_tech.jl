# Transport technologies whose flow is controlled directly
const ControllableTransportTechnology =
    Union{PSIP.AggregateTransportTechnology, PSIP.NodalHVDCTransportTechnology}

#! format: off
_supported_investment_formulations(::Type{<:PSIP.TransmissionTechnology}) = (ContinuousInvestment, IntegerInvestment, BinaryInvestment)

# New capacity is limited by the maximum cumulative capacity constraint, which accounts for
# the existing capacity
get_variable_upper_bound(::BuildCapacity, d::PSIP.TransmissionTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildCapacity, d::PSIP.TransmissionTechnology, ::InvestmentTechnologyFormulation) = 0.0

# Capacity (MW) added by one unit of the build variable
get_variable_multiplier(::BuildCapacity, d::PSIP.TransmissionTechnology, ::Union{IntegerInvestment, BinaryInvestment}) = PSIP.get_unit_size(d)

# Controllable flows are only limited by the cumulative capacity constraints
get_variable_lower_bound(::FlowActivePowerVariable, d::ControllableTransportTechnology, ::OperationsTechnologyFormulation) = nothing
get_variable_upper_bound(::FlowActivePowerVariable, d::ControllableTransportTechnology, ::OperationsTechnologyFormulation) = nothing
get_variable_lower_bound(::Union{FlowActivePowerFromToVariable, FlowActivePowerToFromVariable}, d::ControllableTransportTechnology, ::BasicDispatchWithLosses) = 0.0
get_variable_upper_bound(::Union{FlowActivePowerFromToVariable, FlowActivePowerToFromVariable}, d::ControllableTransportTechnology, ::BasicDispatchWithLosses) = nothing

# Operations variable bounds: bidirectional flow with magnitude <= capacity
get_variable_lower_bound(::FlowActivePowerVariable, d::PSIP.NodalACTransportTechnology, ::OperationsTechnologyFormulation) = -PSIP.get_capacity_limits(d).max
get_variable_upper_bound(::FlowActivePowerVariable, d::PSIP.NodalACTransportTechnology, ::OperationsTechnologyFormulation) = PSIP.get_capacity_limits(d).max

get_max_cap(d::PSIP.TransmissionTechnology, ::CumulativeCapacity) = PSIP.get_capacity_limits(d).max

_arc(d::PSIP.AggregateTransportTechnology) = (PSIP.get_name(PSIP.get_start_region(d)), PSIP.get_name(PSIP.get_end_region(d)))
_arc(d::PSIP.TransmissionTechnology) = (PSIP.get_name(PSIP.get_start_node(d)), PSIP.get_name(PSIP.get_end_node(d)))

# Proportional loss rate, and constant loss per MW of capacity
_loss_terms(d::ControllableTransportTechnology) = _loss_terms(PSIP.get_line_loss(d))
_loss_terms(loss::Float64) = (loss, 0.0)
_loss_terms(loss::PSY.LinearCurve) = (PSY.get_proportional_term(loss), PSY.get_constant_term(loss))
_loss_terms(::PSY.PiecewiseIncrementalCurve) = error("Piecewise line losses are not supported")

_has_losses(::PSIP.NodalACTransportTechnology) = false
_has_losses(d::ControllableTransportTechnology) = _has_losses(PSIP.get_line_loss(d))
_has_losses(loss::Union{Float64, PSY.LinearCurve}) = any(!iszero, _loss_terms(loss))
_has_losses(::PSY.PiecewiseIncrementalCurve) = true
#! format: on

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

################## Expressions ###################

function add_expression!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    devices::U,
    formulation::S,
) where {
    T <: CumulativeCapacity,
    S <: InvestmentTechnologyFormulation,
    U <: Vector{D},
} where {D <: PSIP.TransmissionTechnology}
    IS.@assert_op length(devices) > 0
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

    for d in devices
        name = PSIP.get_name(d)
        unit_size = get_unit_size(BuildCapacity(), d, S())
        running = JuMP.AffExpr(PSIP.get_existing_capacity_mw(portfolio, d))
        for t in time_steps
            JuMP.add_to_expression!(running, var[name, t], unit_size)
            expression[name, t] = copy(running)
        end
    end

    return
end

function add_to_expression!(
    ::SingleOptimizationContainer,
    ::EnergyBalance,
    ::Vector{<:PSIP.TransmissionTechnology},
    ::OperationsTechnologyFormulation,
    ::TransportModel{SingleRegionBalanceModel},
    args...,
)
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
    V <: Union{MultiRegionBalanceModel, AbstractNodalTransportAggregation},
} where {D <: PSIP.TransmissionTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    variable = get_variable(container, FlowActivePowerVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        from, to = _arc(d)
        _add_to_jump_expression!(expression[from, t], variable[name, t], -1.0)
        _add_to_jump_expression!(expression[to, t], variable[name, t], 1.0)
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    ::S,
    ::TransportModel{V},
    tech_model_vector::Vector{X},
) where {
    T <: EnergyBalance,
    S <: BasicDispatchWithLosses,
    U <: Vector{D},
    V <: Union{MultiRegionBalanceModel, AbstractNodalTransportAggregation},
    X <: TechnologyModel,
} where {D <: ControllableTransportTechnology}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    tech_model = string(S)

    from_to = get_variable(container, FlowActivePowerFromToVariable(), D, tech_model)
    to_from = get_variable(container, FlowActivePowerToFromVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        from, to = _arc(d)
        rate, constant = _loss_terms(d)
        inv_model = string(get_investment_formulation(tech_model_vector[ix]))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for op_ix in get_operational_indexes(time_mapping)
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in consecutive_slices[op_ix],
                (node, sent, received) in ((from, from_to, to_from), (to, to_from, from_to))

                _add_to_jump_expression!(expression[node, t], sent[name, t], -1.0)
                _add_to_jump_expression!(expression[node, t], received[name, t], 1.0 - rate)
                JuMP.add_to_expression!(
                    expression[node, t],
                    -constant / 2,
                    installed_cap[name, time_step_inv],
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
    T <: ActivePowerLimitsConstraint,
    S <: BasicDispatch,
    U <: Vector{D},
    V <: FlowActivePowerVariable,
    X <: TechnologyModel,
} where {D <: ControllableTransportTechnology}
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

# Both directions share the capacity
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: ActivePowerLimitsConstraint,
    S <: BasicDispatchWithLosses,
    U <: Vector{D},
    X <: TechnologyModel,
} where {D <: ControllableTransportTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
    con = add_constraints_container!(
        container,
        T(),
        D,
        PSIP.get_name.(devices),
        time_steps,
        meta=tech_model,
    )

    from_to = get_variable(container, FlowActivePowerFromToVariable(), D, tech_model)
    to_from = get_variable(container, FlowActivePowerToFromVariable(), D, tech_model)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        inv_model = string(get_investment_formulation(tech_model_vector[ix]))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for op_ix in get_operational_indexes(time_mapping)
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in consecutive_slices[op_ix]
                con[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    from_to[name, t] + to_from[name, t] <=
                    installed_cap[name, time_step_inv]
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
    S <: InvestmentTechnologyFormulation,
    U <: Vector{D},
    V <: CumulativeCapacity,
} where {D <: PSIP.TransmissionTechnology}
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
    return
end

########################### Objective Function Calls#############################################

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::S,
) where {T <: PSIP.TransmissionTechnology, S <: InvestmentTechnologyFormulation}
    tech_model = string(S)
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    return
end

########################### Nodal AC Transport Technology Methods #################################

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
    return
end
