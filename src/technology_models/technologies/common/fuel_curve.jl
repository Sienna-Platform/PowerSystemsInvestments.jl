"""
Throw an error for a variable cost curve type that the formulations do not support yet.
Variable costs must be a `PSY.CostCurve{PSY.LinearCurve}` or a `PSY.FuelCurve{PSY.LinearCurve}`.
"""
function throw_unsupported_curve(curve::PSY.ProductionVariableCostCurve)
    error(
        "Variable cost curves of type $(typeof(curve)) are not currently supported. Use a " *
        "CostCurve{LinearCurve} or a FuelCurve{LinearCurve}.",
    )
end

_is_fuel_curve(::PSY.ProductionVariableCostCurve) = false
_is_fuel_curve(::PSY.FuelCurve) = true

"""
Whether the variable cost of a technology is defined by a `PSY.FuelCurve`, that is, by a heat
rate and a fuel price instead of a cost per MWh.
"""
has_fuel_curve(d::PSIP.SupplyTechnology) =
    _is_fuel_curve(PSY.get_variable(PSIP.get_operation_costs(d)))

"""
Fuel consumed per MWh generated. Only linear fuel curves are supported, and their constant
(no-load) term is not modeled.
"""
get_heat_rate(fuel_curve::PSY.FuelCurve{PSY.LinearCurve}) =
    PSY.get_proportional_term(PSY.get_value_curve(fuel_curve))

get_heat_rate(fuel_curve::PSY.FuelCurve) = throw_unsupported_curve(fuel_curve)

"""
Price per unit of fuel. Only constant fuel prices are supported.
"""
get_fuel_price(fuel_curve::PSY.FuelCurve) = _get_fuel_price(PSY.get_fuel_cost(fuel_curve))

_get_fuel_price(fuel_price::Float64) = fuel_price

function _get_fuel_price(::IS.TimeSeriesKey)
    error(
        "Time-varying fuel prices are not currently supported. Use a constant fuel price.",
    )
end
