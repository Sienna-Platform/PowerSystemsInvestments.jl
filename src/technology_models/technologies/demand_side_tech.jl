#! format: off
_supported_investment_formulations(::Type{<:PSIP.DemandSideTechnology}) = (ContinuousInvestment, IntegerInvestment, BinaryInvestment)

get_variable_lower_bound(::VariableType, d::PSIP.DemandSideTechnology, ::AbstractTechnologyFormulation) = 0.0
get_variable_upper_bound(::VariableType, d::PSIP.DemandSideTechnology, ::AbstractTechnologyFormulation) = nothing

# Capacity (MW) added by one unit of the build variable
get_variable_multiplier(::BuildCapacity, d::PSIP.DemandSideTechnology, ::Union{IntegerInvestment, BinaryInvestment}) = PSIP.get_unit_size(d)

get_cumulative_limits(d::PSIP.DemandSideTechnology, ::CumulativeCapacity) = PSIP.get_capacity_limits(d)

get_expression_multiplier(::EnergyBalance, ::ActiveInPowerVariable, ::PSIP.DemandSideTechnology, ::OperationsTechnologyFormulation) = -1.0
#! format: on

get_default_attributes(
    ::Type{<:PSIP.DemandSideTechnology},
    ::Type{<:InvestmentTechnologyFormulation},
    ::Type{<:OperationsTechnologyFormulation},
    ::Type{<:FeasibilityTechnologyFormulation},
) = Dict{String, Any}()

# Value of one MWh consumed (USD/MWh): the price of the product over the MWh per unit
_product_price(curve::PSY.LinearCurve) = IS.get_proportional_term(curve)
function _product_price(curve::PSY.ValueCurve)
    error("Product prices of type $(typeof(curve)) are not supported. Use a LinearCurve.")
end

function check_end_use(d::PSIP.DemandSideTechnology)
    name = PSIP.get_name(d)
    if PSIP.get_technology_efficiency(d) <= 0.0
        error("technology_efficiency of $name must be positive (MWh per unit of product).")
    end
    if !(0.0 <= PSIP.get_min_power(d) <= 1.0)
        error(
            "min_power of $name is a fraction of its capacity and must be between 0 and 1.",
        )
    end
    if _product_price(PSIP.get_price_per_unit(d)) > 0.0 &&
       PSIP.get_capacity_limits(d).max >= 1e8
        @warn "$name earns $(PSIP.get_price_per_unit(d)) per unit of product and has no " *
              "maximum capacity, so its build is only limited by what it can sell. Set " *
              "capacity_limits."
    end
    return
end

################## Expressions ###################

# Existing capacity plus the capacity built up to each investment period
function add_expression!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: CumulativeCapacity,
    U <: Vector{D},
    V <: InvestmentTechnologyFormulation,
} where {D <: PSIP.DemandSideTechnology}
    IS.@assert_op length(devices) > 0
    time_steps = get_investment_time_steps(get_time_mapping(container))
    tech_model = string(V)
    build = get_variable(container, BuildCapacity(), D, tech_model)
    expression = add_expression_container!(
        container,
        expression_type,
        D,
        PSIP.get_name.(devices),
        time_steps,
        meta=tech_model,
    )
    for d in devices
        name = PSIP.get_name(d)
        unit_size = get_unit_size(BuildCapacity(), d, V())
        running = JuMP.AffExpr(PSIP.get_existing_capacity_mw(portfolio, d))
        for t in time_steps
            JuMP.add_to_expression!(running, unit_size, build[name, t])
            expression[name, t] = copy(running)
        end
    end
    return
end

# Containers of the variable cost and the product revenue of each technology, for results
function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: Union{VariableOMCost, ProductRevenue},
    U <: Vector{D},
    V <: EndUseDispatch,
} where {D <: PSIP.DemandSideTechnology}
    add_expression_container!(
        container,
        expression_type,
        D,
        PSIP.get_name.(devices),
        get_time_steps(get_time_mapping(container)),
        meta=string(V),
    )
    return
end

# Consumption is withdrawn from the energy balance of its region
function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    ::V,
    devices::U,
    formulation::S,
    transport_model::TransportModel,
) where {
    T <: EnergyBalance,
    V <: ActiveInPowerVariable,
    S <: EndUseDispatch,
    U <: Vector{D},
} where {D <: PSIP.DemandSideTechnology}
    IS.@assert_op length(devices) > 0
    expression = get_expression(container, T(), PSIP.Portfolio)
    consumption = get_variable(container, V(), D, string(S))
    for d in devices, t in get_operational_time_steps(get_time_mapping(container))
        JuMP.add_to_expression!(
            expression[_balance_region(transport_model, d), t],
            get_expression_multiplier(T(), V(), d, formulation),
            consumption[PSIP.get_name(d), t],
        )
    end
    return
end

# Adds coefficient times the consumption of an end-use technology at each time step to the
# expression `expression_at(t)`
function _add_end_use_consumption!(
    expression_at::Function,
    container::SingleOptimizationContainer,
    d::PSIP.DemandSideTechnology,
    formulation::OperationsTechnologyFormulation,
    time_steps,
    coefficient::Float64,
)
    consumption = get_variable(
        container,
        ActiveInPowerVariable(),
        typeof(d),
        string(typeof(formulation)),
    )
    for t in time_steps
        JuMP.add_to_expression!(
            expression_at(t),
            coefficient,
            consumption[PSIP.get_name(d), t],
        )
    end
    return
end

################## Constraints ###################

# Consumption is between min_power and all of the capacity installed in the period
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: InputActivePowerVariableLimitsConstraint,
    V <: ActiveInPowerVariable,
    S <: EndUseDispatch,
    U <: Vector{D},
    X <: TechnologyModel,
} where {D <: PSIP.DemandSideTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_operational_time_steps(time_mapping)
    tech_model = string(S)
    names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        names,
        time_steps,
        meta="$(tech_model)_ub",
    )
    con_lb = add_constraints_container!(
        container,
        T(),
        D,
        names,
        time_steps,
        meta="$(tech_model)_lb",
    )
    consumption = get_variable(container, V(), D, tech_model)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    jump_model = get_jump_model(container)
    for (d, model) in zip(devices, tech_model_vector)
        name = PSIP.get_name(d)
        inv_model = string(get_investment_formulation(model))
        capacity = get_expression(container, CumulativeCapacity(), D, inv_model)
        min_power = PSIP.get_min_power(d)
        for op_ix in get_operational_indexes(time_mapping), t in consecutive_slices[op_ix]
            installed = capacity[name, inverse_invest_mapping[op_ix]]
            con_ub[name, t] =
                JuMP.@constraint(jump_model, consumption[name, t] <= installed)
            con_lb[name, t] =
                JuMP.@constraint(jump_model, consumption[name, t] >= min_power * installed)
        end
    end
    return
end

# Consumption changes by at most the ramp limits (fraction of capacity per hour) between steps
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: RampRateConstraint,
    V <: ActiveInPowerVariable,
    S <: EndUseDispatch,
    U <: Vector{D},
    X <: TechnologyModel,
} where {D <: PSIP.DemandSideTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_operational_time_steps(time_mapping)
    tech_model = string(S)
    names = PSIP.get_name.(devices)
    con_up = add_constraints_container!(
        container,
        T(),
        D,
        names,
        time_steps,
        meta="$(tech_model)_up",
    )
    con_dn = add_constraints_container!(
        container,
        T(),
        D,
        names,
        time_steps,
        meta="$(tech_model)_dn",
    )
    consumption = get_variable(container, V(), D, tech_model)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    jump_model = get_jump_model(container)
    for (d, model) in zip(devices, tech_model_vector)
        name = PSIP.get_name(d)
        inv_model = string(get_investment_formulation(model))
        capacity = get_expression(container, CumulativeCapacity(), D, inv_model)
        ramp_limits = PSIP.get_ramp_limits(d)
        for op_ix in get_operational_indexes(time_mapping)
            hours = get_time_step_length(time_mapping, op_ix)
            ramp_up = min(1.0, ramp_limits.up * hours)
            ramp_down = min(1.0, ramp_limits.down * hours)
            for t in consecutive_slices[op_ix]
                installed = capacity[name, inverse_invest_mapping[op_ix]]
                change =
                    consumption[name, t] -
                    consumption[name, get_previous_time_step(time_mapping, op_ix, t)]
                con_up[name, t] =
                    JuMP.@constraint(jump_model, change <= ramp_up * installed)
                con_dn[name, t] =
                    JuMP.@constraint(jump_model, -change <= ramp_down * installed)
            end
        end
    end
    return
end

############### Objective Function ###############

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::B,
) where {T <: PSIP.DemandSideTechnology, B <: InvestmentTechnologyFormulation}
    tech_model = string(B)
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(container, CumulativeCapacity(), devices, formulation, tech_model)
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::C,
) where {T <: PSIP.DemandSideTechnology, C <: EndUseDispatch}
    tech_model = string(C)
    add_variable_cost!(container, ActiveInPowerVariable(), devices, formulation, tech_model)
    add_product_revenue!(
        container,
        ActiveInPowerVariable(),
        devices,
        formulation,
        tech_model,
    )
    return
end

function add_variable_cost!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {T <: PSIP.DemandSideTechnology, U <: ActiveInPowerVariable, V <: EndUseDispatch}
    for d in devices
        _add_cost_to_objective!(
            container,
            U(),
            d,
            PSIP.get_operation_costs(d),
            V(),
            tech_model,
        )
    end
    return
end

# Value of the product, price / technology_efficiency per MWh consumed, weighted and
# discounted as the variable cost
function add_product_revenue!(
    container::SingleOptimizationContainer,
    ::U,
    devices::Vector{T},
    ::V,
    tech_model::String,
) where {T <: PSIP.DemandSideTechnology, U <: ActiveInPowerVariable, V <: EndUseDispatch}
    for d in devices
        value =
            _product_price(PSIP.get_price_per_unit(d)) / PSIP.get_technology_efficiency(d)
        iszero(value) && continue
        _add_linearcurve_cost!(
            container,
            U(),
            ProductRevenue(),
            d,
            PSIP.get_operation_costs(d),
            -value,
            tech_model,
        )
    end
    return
end
