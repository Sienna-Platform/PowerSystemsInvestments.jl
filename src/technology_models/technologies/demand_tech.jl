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

# Region of the energy balance a demand is in
_balance_region(::TransportModel{SingleRegionBalanceModel}, ::PSIP.ProjectedDemand) =
    SINGLE_REGION
_balance_region(::TransportModel, d::PSIP.ProjectedDemand) =
    PSIP.get_name(only(PSIP.get_region(d)))

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
    S <: UnservedDemandDispatch,
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
    formulation::UnservedDemandDispatch,
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

# Cost of unserved demand, weighted and discounted as other operating costs
function objective_function!(
    container::SingleOptimizationContainer,
    devices::U,
    formulation::S,
) where {S <: UnservedDemandDispatch, U <: Vector{D}} where {D <: PSIP.ProjectedDemand}
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
    formulation::UnservedDemandDispatch,
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
