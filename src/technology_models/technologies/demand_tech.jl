_supported_investment_formulations(::Type{<:PSIP.ProjectedDemand}) = (StaticLoadInvestment,)

function get_default_time_series_names(::Type{U}) where {U <: PSIP.ProjectedDemand}
    # TODO: We need to discuss about an API for timeseries names for users
    return "ops_demand"
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U <: PSIP.ProjectedDemand,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
    X <: FeasibilityTechnologyFormulation,
}
    return Dict{String, Any}()
end

# Region of the energy balance a demand or end-use technology is in
_balance_region(
    ::TransportModel{SingleRegionBalanceModel},
    ::Union{PSIP.ProjectedDemand, PSIP.DemandSideTechnology},
) = SINGLE_REGION
_balance_region(
    ::TransportModel,
    d::Union{PSIP.ProjectedDemand, PSIP.DemandSideTechnology},
) = PSIP.get_name(only(PSIP.get_region(d)))

################### Unserved demand ####################

# Curtailment tiers of a demand: the fraction of demand each one covers and its price (USD/MWh)
function _curtailment_tiers(curve::PSY.LinearCurve, max_curtailment::Float64)
    if IS.get_constant_term(curve) != 0.0
        error("A curtailment cost must be zero when nothing is curtailed.")
    end
    max_curtailment == 0.0 && return Tuple{Float64, Float64}[]
    return [(max_curtailment, IS.get_proportional_term(curve))]
end

function _curtailment_tiers(curve::PSY.PiecewiseIncrementalCurve, max_curtailment::Float64)
    x_coords = IS.get_x_coords(curve)
    slopes = IS.get_slopes(curve)
    if first(x_coords) != 0.0 ||
       !isapprox(last(x_coords), max_curtailment) ||
       !issorted(x_coords; lt=<=)
        error(
            "The x coordinates of a piecewise curtailment cost are fractions of demand: " *
            "they must start at 0, increase, and end at max_demand_curtailment " *
            "($(max_curtailment)). Got $(x_coords)." *
            (max_curtailment == 0.0 ? " Is max_demand_curtailment unset?" : ""),
        )
    end
    return [(x_coords[k + 1] - x_coords[k], slopes[k]) for k in eachindex(slopes)]
end

function _curtailment_tiers(curve::PSY.ValueCurve, ::Float64)
    error(
        "Curtailment costs of type $(typeof(curve)) are not supported. Use a LinearCurve " *
        "or a PiecewiseIncrementalCurve.",
    )
end

# Tiers of a demand's unserved demand: its curtailment tiers, then the rest of the demand,
# shed involuntarily at the value of lost load
function _unserved_tiers(d::PSIP.ProjectedDemand)
    max_curtailment = PSIP.get_max_demand_curtailment(d)
    if !(0.0 <= max_curtailment <= 1.0)
        error(
            "max_demand_curtailment of demand $(PSIP.get_name(d)) is a fraction of " *
            "demand and must be between 0 and 1. Got $(max_curtailment).",
        )
    end
    tiers = _curtailment_tiers(PSIP.get_curtailment_cost(d), max_curtailment)
    push!(tiers, (1.0 - max_curtailment, PSIP.get_value_of_lost_load(d)))
    if any(<(0.0), last.(tiers))
        error(
            "The unserved demand prices of demand $(PSIP.get_name(d)) must be non-negative.",
        )
    end
    return tiers
end

# Variable names of the tiers of a demand's unserved demand
_unserved_names(d::PSIP.ProjectedDemand) =
    ["$(PSIP.get_name(d))__tier$(k)" for k in eachindex(_unserved_tiers(d))]

# Each tier of unserved demand is at most its share of the demand
function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    devices::U,
    formulation::S,
) where {
    T <: UnservedDemandVariable,
    S <: Union{UnservedDemandDispatch, FlexibleDemandDispatch},
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    IS.@assert_op length(devices) > 0
    time_steps = get_operational_time_steps(get_time_mapping(container))
    names = [name for d in devices for name in _unserved_names(d)]
    variable = add_variable_container!(
        container,
        variable_type,
        D,
        names,
        time_steps,
        meta=string(S),
    )
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    demand = get_expression(container, DemandExpression(), PSIP.Portfolio)
    for d in devices
        tiers = _unserved_tiers(d)
        max_curtailment = PSIP.get_max_demand_curtailment(d)
        # A piecewise curtailment cost needs a positive max_demand_curtailment, so a demand
        # without curtailment has a linear cost here
        if max_curtailment == 0.0 &&
           IS.get_proportional_term(PSIP.get_curtailment_cost(d)) != 0.0
            @warn "Demand $(PSIP.get_name(d)) has a curtailment_cost but its " *
                  "max_demand_curtailment is 0, so it is never curtailed."
        elseif max_curtailment > 0.0 && all(iszero, last.(tiers[1:(end - 1)]))
            @warn "Demand $(PSIP.get_name(d)) can curtail $(max_curtailment) of its " *
                  "demand at no cost. Set its curtailment_cost."
        end
        for ((share, _), name) in zip(tiers, _unserved_names(d)), t in time_steps
            variable[name, t] = JuMP.@variable(
                jump_model,
                lower_bound = 0.0,
                upper_bound = share * JuMP.constant(demand[PSIP.get_name(d), t]),
                base_name = store_names ? "$(T)_$(D)_{$(name), $(t)}" : "",
            )
        end
    end
    return
end

# Adds coefficient times a demand's unserved demand at each time step to the expression
# `expression_at(t)`. With `credited`, only the curtailment a capacity reserve margin
# credits, not the involuntary shedding (the last tier).
function _add_unserved_demand!(
    expression_at::Function,
    container::SingleOptimizationContainer,
    d::PSIP.ProjectedDemand,
    formulation::Union{UnservedDemandDispatch, FlexibleDemandDispatch},
    time_steps,
    coefficient::Float64;
    credited::Bool=false,
)
    variable = get_variable(
        container,
        UnservedDemandVariable(),
        typeof(d),
        string(typeof(formulation)),
    )
    names = _unserved_names(d)
    for name in (credited ? names[1:(end - 1)] : names)
        for t in time_steps
            JuMP.add_to_expression!(expression_at(t), coefficient, variable[name, t])
        end
    end
    return
end

_add_unserved_demand!(
    ::Function,
    ::SingleOptimizationContainer,
    ::PSIP.ProjectedDemand,
    ::OperationsTechnologyFormulation,
    time_steps,
    ::Float64;
    credited::Bool=false,
) = nothing

function objective_function!(
    container::SingleOptimizationContainer,
    devices::U,
    formulation::S,
) where {S <: UnservedDemandDispatch, U <: Vector{D}} where {D <: PSIP.ProjectedDemand}
    add_unserved_demand_cost!(container, UnservedDemandVariable(), devices, formulation)
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::U,
    formulation::S,
) where {S <: FlexibleDemandDispatch, U <: Vector{D}} where {D <: PSIP.ProjectedDemand}
    add_unserved_demand_cost!(container, UnservedDemandVariable(), devices, formulation)
    add_shift_cost!(container, DemandDeferredVariable(), devices, formulation)
    return
end

# Cost of unserved demand, weighted and discounted as other operating costs
function add_unserved_demand_cost!(
    container::SingleOptimizationContainer,
    ::UnservedDemandVariable,
    devices::U,
    formulation::S,
) where {
    S <: Union{UnservedDemandDispatch, FlexibleDemandDispatch},
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    variable = get_variable(container, UnservedDemandVariable(), D, string(S))
    for d in devices
        tiers = _unserved_tiers(d)
        names = _unserved_names(d)
        for op_ix in get_operational_indexes(time_mapping)
            factor =
                get_time_step_weight(container, op_ix) *
                _period_cost_factor(container, inverse_invest_mapping[op_ix])
            for t in consecutive_slices[op_ix]
                for ((_, price), name) in zip(tiers, names)
                    add_to_objective_operations_expression!(
                        container,
                        factor * price * variable[name, t],
                    )
                end
            end
        end
    end
    return
end

################### Flexible demand ####################

#! format: off
get_expression_multiplier(::EnergyBalance, ::DemandDeferredVariable, ::PSIP.ProjectedDemand, ::FlexibleDemandDispatch) = 1.0
get_expression_multiplier(::EnergyBalance, ::DemandRecoveredVariable, ::PSIP.ProjectedDemand, ::FlexibleDemandDispatch) = -1.0
#! format: on

# Price of shifting demand (USD/MWh shifted)
_shift_price(curve::PSY.LinearCurve) = IS.get_proportional_term(curve)
function _shift_price(curve::PSY.ValueCurve)
    error("Shift costs of type $(typeof(curve)) are not supported. Use a LinearCurve.")
end

function check_flexible_demand(d::PSIP.ProjectedDemand)
    name = PSIP.get_name(d)
    flexible_fraction = PSIP.get_flexible_fraction(d)
    if !(0.0 <= flexible_fraction <= 1.0)
        error("flexible_fraction of demand $name must be between 0 and 1.")
    end
    if !(0.0 < PSIP.get_shift_efficiency(d) <= 1.0)
        error("shift_efficiency of demand $name must be in (0, 1].")
    end
    if PSIP.get_max_demand_delay(d) < 0.0 || PSIP.get_max_demand_advance(d) < 0.0
        error("The shifting windows of demand $name must be non-negative.")
    end
    if _shift_price(PSIP.get_shift_cost(d)) < 0.0
        error("The shift cost of demand $name must be non-negative.")
    end
    if flexible_fraction == 0.0 ||
       PSIP.get_max_demand_delay(d) == PSIP.get_max_demand_advance(d) == 0.0
        @warn "Demand $name uses FlexibleDemandDispatch but has no flexible_fraction or " *
              "no shifting window, so none of its demand can be shifted."
    end
    return
end

# Number of time steps covered by a shifting window of `hours`. A window of 0 hours forbids
# shifting in that direction, and a window can't reach past its own representative period,
# which wraps around.
function _shift_window(time_mapping::TimeMapping, op_ix::Int, hours::Float64)
    hours == 0.0 && return 0
    return min(
        get_commitment_time_steps(time_mapping, op_ix, hours),
        length(get_consecutive_slices(time_mapping)[op_ix]) - 1,
    )
end

# Deferred demand is at most the flexible share of the demand in its time step. Recovered
# demand is at most the flexible share of the peak of the representative period, so the
# backlog can't all be served in one step.
_shift_limit(::DemandDeferredVariable, demand::Float64, ::Float64) = demand
_shift_limit(::DemandRecoveredVariable, ::Float64, peak::Float64) = peak

function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    devices::U,
    formulation::S,
) where {
    T <: Union{DemandDeferredVariable, DemandRecoveredVariable},
    S <: FlexibleDemandDispatch,
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    variable = add_variable_container!(
        container,
        variable_type,
        D,
        PSIP.get_name.(devices),
        get_operational_time_steps(time_mapping),
        meta=string(S),
    )
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    demand = get_expression(container, DemandExpression(), PSIP.Portfolio)
    for d in devices, op_ix in get_operational_indexes(time_mapping)
        name = PSIP.get_name(d)
        time_slices = consecutive_slices[op_ix]
        peak = maximum(JuMP.constant(demand[name, t]) for t in time_slices)
        for t in time_slices
            limit = _shift_limit(variable_type, JuMP.constant(demand[name, t]), peak)
            variable[name, t] = JuMP.@variable(
                jump_model,
                lower_bound = 0.0,
                upper_bound = PSIP.get_flexible_fraction(d) * limit,
                base_name = store_names ? "$(T)_$(D)_{$(name), $(t)}" : "",
            )
        end
    end
    return
end

function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    devices::U,
    formulation::S,
) where {
    T <: DemandBacklogVariable,
    S <: FlexibleDemandDispatch,
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    IS.@assert_op length(devices) > 0
    time_steps = get_operational_time_steps(get_time_mapping(container))
    variable = add_variable_container!(
        container,
        variable_type,
        D,
        PSIP.get_name.(devices),
        time_steps,
        meta=string(S),
    )
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        variable[name, t] = JuMP.@variable(
            jump_model,
            base_name = store_names ? "$(T)_$(D)_{$(name), $(t)}" : "",
        )
    end
    return
end

# The backlog grows with deferred demand and shrinks with recovered demand, of which only
# shift_efficiency is kept. It wraps around each representative period.
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    formulation::S,
) where {
    T <: DemandBacklogConstraint,
    S <: FlexibleDemandDispatch,
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    tech_model = string(S)
    con = add_constraints_container!(
        container,
        T(),
        D,
        PSIP.get_name.(devices),
        get_operational_time_steps(time_mapping),
        meta=tech_model,
    )
    deferred = get_variable(container, DemandDeferredVariable(), D, tech_model)
    recovered = get_variable(container, DemandRecoveredVariable(), D, tech_model)
    backlog = get_variable(container, DemandBacklogVariable(), D, tech_model)
    jump_model = get_jump_model(container)
    for d in devices, op_ix in get_operational_indexes(time_mapping)
        name = PSIP.get_name(d)
        efficiency = PSIP.get_shift_efficiency(d)
        hours = get_time_step_length(time_mapping, op_ix)
        for t in consecutive_slices[op_ix]
            previous = get_previous_time_step(time_mapping, op_ix, t)
            con[name, t] = JuMP.@constraint(
                jump_model,
                backlog[name, t] ==
                backlog[name, previous] +
                hours * (deferred[name, t] - efficiency * recovered[name, t])
            )
        end
    end
    return
end

# Demand deferred and not yet served at the end of a time step is served within the next
# max_demand_delay hours
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    formulation::S,
) where {
    T <: DemandDelayConstraint,
    S <: FlexibleDemandDispatch,
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    tech_model = string(S)
    con = add_constraints_container!(
        container,
        T(),
        D,
        PSIP.get_name.(devices),
        get_operational_time_steps(time_mapping),
        meta=tech_model,
    )
    recovered = get_variable(container, DemandRecoveredVariable(), D, tech_model)
    backlog = get_variable(container, DemandBacklogVariable(), D, tech_model)
    jump_model = get_jump_model(container)
    for d in devices, op_ix in get_operational_indexes(time_mapping)
        name = PSIP.get_name(d)
        energy = PSIP.get_shift_efficiency(d) * get_time_step_length(time_mapping, op_ix)
        window = _shift_window(time_mapping, op_ix, PSIP.get_max_demand_delay(d))
        for t in consecutive_slices[op_ix]
            served = JuMP.AffExpr(0.0)
            for k in 1:window
                next = get_previous_time_step(time_mapping, op_ix, t, -k)
                JuMP.add_to_expression!(served, energy, recovered[name, next])
            end
            con[name, t] = JuMP.@constraint(jump_model, served >= backlog[name, t])
        end
    end
    return
end

# Demand served early is deferred within the next max_demand_advance hours
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    formulation::S,
) where {
    T <: DemandAdvanceConstraint,
    S <: FlexibleDemandDispatch,
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    tech_model = string(S)
    con = add_constraints_container!(
        container,
        T(),
        D,
        PSIP.get_name.(devices),
        get_operational_time_steps(time_mapping),
        meta=tech_model,
    )
    deferred = get_variable(container, DemandDeferredVariable(), D, tech_model)
    backlog = get_variable(container, DemandBacklogVariable(), D, tech_model)
    jump_model = get_jump_model(container)
    for d in devices, op_ix in get_operational_indexes(time_mapping)
        name = PSIP.get_name(d)
        hours = get_time_step_length(time_mapping, op_ix)
        window = _shift_window(time_mapping, op_ix, PSIP.get_max_demand_advance(d))
        for t in consecutive_slices[op_ix]
            later = JuMP.AffExpr(0.0)
            for k in 1:window
                next = get_previous_time_step(time_mapping, op_ix, t, -k)
                JuMP.add_to_expression!(later, hours, deferred[name, next])
            end
            con[name, t] = JuMP.@constraint(jump_model, later >= -backlog[name, t])
        end
    end
    return
end

# The same demand can't be both deferred and unserved
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    formulation::S,
) where {
    T <: DemandDeferralLimitConstraint,
    S <: FlexibleDemandDispatch,
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    time_steps = get_operational_time_steps(get_time_mapping(container))
    con = add_constraints_container!(
        container,
        T(),
        D,
        PSIP.get_name.(devices),
        time_steps,
        meta=string(S),
    )
    deferred = get_variable(container, DemandDeferredVariable(), D, string(S))
    demand = get_expression(container, DemandExpression(), PSIP.Portfolio)
    jump_model = get_jump_model(container)
    for d in devices
        name = PSIP.get_name(d)
        reduction =
            Dict(t => JuMP.AffExpr(0.0, deferred[name, t] => 1.0) for t in time_steps)
        _add_unserved_demand!(t -> reduction[t], container, d, formulation, time_steps, 1.0)
        for t in time_steps
            con[name, t] =
                JuMP.@constraint(jump_model, reduction[t] <= JuMP.constant(demand[name, t]))
        end
    end
    return
end

# Shift cost on deferred demand, so each MWh shifted is charged once
function add_shift_cost!(
    container::SingleOptimizationContainer,
    ::V,
    devices::U,
    formulation::S,
) where {
    V <: DemandDeferredVariable,
    S <: FlexibleDemandDispatch,
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    deferred = get_variable(container, V(), D, string(S))
    for d in devices
        price = _shift_price(PSIP.get_shift_cost(d))
        price == 0.0 && continue
        name = PSIP.get_name(d)
        for op_ix in get_operational_indexes(time_mapping)
            factor =
                get_time_step_weight(container, op_ix) *
                _period_cost_factor(container, inverse_invest_mapping[op_ix])
            for t in consecutive_slices[op_ix]
                add_to_objective_operations_expression!(
                    container,
                    factor * price * deferred[name, t],
                )
            end
        end
    end
    return
end

# Adds coefficient times the net demand a demand shifts into each time step (recovered minus
# deferred) to the expression `expression_at(t)`
function _add_demand_shift!(
    expression_at::Function,
    container::SingleOptimizationContainer,
    d::PSIP.ProjectedDemand,
    formulation::FlexibleDemandDispatch,
    time_steps,
    coefficient::Float64,
)
    tech_model = string(typeof(formulation))
    deferred = get_variable(container, DemandDeferredVariable(), typeof(d), tech_model)
    recovered = get_variable(container, DemandRecoveredVariable(), typeof(d), tech_model)
    name = PSIP.get_name(d)
    for t in time_steps
        JuMP.add_to_expression!(expression_at(t), coefficient, recovered[name, t])
        JuMP.add_to_expression!(expression_at(t), -coefficient, deferred[name, t])
    end
    return
end

_add_demand_shift!(
    ::Function,
    ::SingleOptimizationContainer,
    ::PSIP.ProjectedDemand,
    ::OperationsTechnologyFormulation,
    time_steps,
    ::Float64,
) = nothing

################## Expressions ###################

# Demand is withdrawn from the energy balance of its region
function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    ::OperationsTechnologyFormulation,
    transport_model::TransportModel,
) where {T <: EnergyBalance, U <: Vector{D}} where {D <: PSIP.ProjectedDemand}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    expression = get_expression(container, T(), PSIP.Portfolio)
    time_steps = get_operational_time_steps(time_mapping)
    demand = get_expression(container, DemandExpression(), PSIP.Portfolio)
    for d in devices
        region = _balance_region(transport_model, d)
        for t in time_steps
            JuMP.add_to_expression!(
                expression[region, t],
                -1.0,
                demand[PSIP.get_name(d), t],
            )
        end
    end
    return
end

# Unserved demand is given back to the energy balance of its region
function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    ::UnservedDemandVariable,
    devices::U,
    formulation::Union{UnservedDemandDispatch, FlexibleDemandDispatch},
    transport_model::TransportModel,
) where {T <: EnergyBalance, U <: Vector{D}} where {D <: PSIP.ProjectedDemand}
    IS.@assert_op length(devices) > 0
    expression = get_expression(container, T(), PSIP.Portfolio)
    time_steps = get_operational_time_steps(get_time_mapping(container))
    for d in devices
        region = _balance_region(transport_model, d)
        _add_unserved_demand!(
            t -> expression[region, t],
            container,
            d,
            formulation,
            time_steps,
            1.0,
        )
    end
    return
end

# Deferred demand is given back to the energy balance of its region, and recovered demand is
# withdrawn from it
function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    ::V,
    devices::U,
    formulation::S,
    transport_model::TransportModel,
) where {
    T <: EnergyBalance,
    V <: Union{DemandDeferredVariable, DemandRecoveredVariable},
    S <: FlexibleDemandDispatch,
    U <: Vector{D},
} where {D <: PSIP.ProjectedDemand}
    IS.@assert_op length(devices) > 0
    expression = get_expression(container, T(), PSIP.Portfolio)
    variable = get_variable(container, V(), D, string(S))
    for d in devices, t in get_operational_time_steps(get_time_mapping(container))
        name = PSIP.get_name(d)
        JuMP.add_to_expression!(
            expression[_balance_region(transport_model, d), t],
            get_expression_multiplier(T(), V(), d, formulation),
            variable[name, t],
        )
    end
    return
end

# Weighted (representative-day) demand per operational index, aggregated by the region or
# node of the demand. A numeric constant, the gross demand.
function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    ::OperationsTechnologyFormulation,
    transport_model::TransportModel,
) where {T <: WeightedEnergyDemand, U <: Vector{D}} where {D <: PSIP.ProjectedDemand}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    expression = get_expression(container, T(), PSIP.Portfolio)
    demand = get_expression(container, DemandExpression(), PSIP.Portfolio)
    for d in devices
        region = _balance_region(transport_model, d)
        for op_ix in get_operational_indexes(time_mapping), t in consecutive_slices[op_ix]
            JuMP.add_to_expression!(
                expression[region, op_ix],
                get_time_step_weight(container, op_ix),
                demand[PSIP.get_name(d), t],
            )
        end
    end
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatchFeasibility,
    transport_model::TransportModel,
) where {T <: FeasibilitySurplus, U <: Vector{D}} where {D <: PSIP.ProjectedDemand}
    IS.@assert_op length(devices) > 0
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    expression = get_expression(container, T(), PSIP.Portfolio)
    demand = get_expression(container, DemandExpression(), PSIP.Portfolio)
    for d in devices
        region = _balance_region(transport_model, d)
        for op_ix in get_feasibility_indexes(time_mapping), t in consecutive_slices[op_ix]
            JuMP.add_to_expression!(
                expression[region, t],
                -1.0,
                demand[PSIP.get_name(d), t],
            )
        end
    end
    return
end
