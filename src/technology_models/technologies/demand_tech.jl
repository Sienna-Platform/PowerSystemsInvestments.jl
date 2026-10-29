_supported_investment_formulations(::Type{<:PSIP.DemandRequirement}) =
    (StaticLoadInvestment,)

function get_default_time_series_names(::Type{U}) where {U <: PSIP.DemandRequirement}
    # TODO: We need to discuss about an API for timeseries names for users
    return "ops_demand"
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U <: PSIP.DemandRequirement,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
    X <: FeasibilityTechnologyFormulation,
}
    return Dict{String, Any}()
end

# Region of the energy balance a demand is in
_balance_region(::TransportModel{SingleRegionBalanceModel}, ::PSIP.DemandRequirement) =
    SINGLE_REGION
_balance_region(::TransportModel, d::PSIP.DemandRequirement) =
    PSIP.get_name(only(PSIP.get_region(d)))

################### Unserved demand ####################

# Tiers of a demand's unserved demand cost: the fraction of demand each one covers and its
# price (USD/MWh). The quadratic term is added to the objective separately (_quadratic_term).
function _unserved_tiers(curve::Union{PSY.LinearCurve, PSY.QuadraticCurve})
    if IS.get_constant_term(curve) != 0.0
        error("An unserved demand cost must be zero when all demand is served.")
    end
    return [(1.0, IS.get_proportional_term(curve))]
end

function _unserved_tiers(curve::PSY.PiecewiseIncrementalCurve)
    x_coords = IS.get_x_coords(curve)
    slopes = IS.get_slopes(curve)
    if first(x_coords) != 0.0 || last(x_coords) > 1.0 || !issorted(x_coords; lt=<=)
        error(
            "The x coordinates of a piecewise unserved demand cost are fractions of demand: " *
            "they must start at 0, increase, and end at most at 1. Got $(x_coords).",
        )
    end
    if any(<(0.0), slopes)
        error("The prices of an unserved demand cost must be non-negative. Got $(slopes).")
    end
    return [(x_coords[k + 1] - x_coords[k], slopes[k]) for k in eachindex(slopes)]
end

function _unserved_tiers(curve::PSY.ValueCurve)
    error(
        "Unserved demand costs of type $(typeof(curve)) are not supported. Use a " *
        "LinearCurve, a PiecewiseIncrementalCurve or a QuadraticCurve.",
    )
end

_unserved_tiers(d::PSIP.DemandRequirement) =
    _unserved_tiers(PSIP.get_unserved_demand_cost(d))

# Variable names of the tiers of a demand's unserved demand
_unserved_names(d::PSIP.DemandRequirement) =
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
} where {D <: PSIP.DemandRequirement}
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
        for ((share, _), name) in zip(_unserved_tiers(d), _unserved_names(d)),
            t in time_steps

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
# `expression_at(t)`. With `credited`, only the tiers a capacity reserve margin credits:
# every one but the most expensive, which stands for involuntary shedding (if several tie
# for the highest price, none of them is credited).
function _add_unserved_demand!(
    expression_at::Function,
    container::SingleOptimizationContainer,
    d::PSIP.DemandRequirement,
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
    tiers = _unserved_tiers(d)
    highest_price = maximum(last.(tiers))
    for ((_, price), name) in zip(tiers, _unserved_names(d))
        credited && price == highest_price && continue
        for t in time_steps
            JuMP.add_to_expression!(expression_at(t), coefficient, variable[name, t])
        end
    end
    return
end

_add_unserved_demand!(
    ::Function,
    ::SingleOptimizationContainer,
    ::PSIP.DemandRequirement,
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
) where {S <: UnservedDemandDispatch, U <: Vector{D}} where {D <: PSIP.DemandRequirement}
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    variable = get_variable(container, UnservedDemandVariable(), D, string(S))
    for d in devices
        tiers = _unserved_tiers(d)
        names = _unserved_names(d)
        curve = PSIP.get_unserved_demand_cost(d)
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
                quadratic = _quadratic_term(curve)
                if quadratic != 0.0
                    add_to_objective_operations_expression!(
                        container,
                        factor * quadratic * variable[only(names), t]^2,
                    )
                end
            end
        end
    end
    return
end

_quadratic_term(::PSY.ValueCurve) = 0.0
_quadratic_term(curve::PSY.QuadraticCurve) = IS.get_quadratic_term(curve)

################## Expressions ###################

# Demand is withdrawn from the energy balance of its region
function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    ::OperationsTechnologyFormulation,
    transport_model::TransportModel,
) where {T <: EnergyBalance, U <: Vector{D}} where {D <: PSIP.DemandRequirement}
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
) where {T <: EnergyBalance, U <: Vector{D}} where {D <: PSIP.DemandRequirement}
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
) where {T <: WeightedEnergyDemand, U <: Vector{D}} where {D <: PSIP.DemandRequirement}
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
) where {T <: FeasibilitySurplus, U <: Vector{D}} where {D <: PSIP.DemandRequirement}
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
