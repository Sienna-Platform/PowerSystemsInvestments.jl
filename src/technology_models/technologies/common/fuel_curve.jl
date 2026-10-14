function throw_unsupported_curve(curve::PSY.ProductionVariableCostCurve)
    error(
        "Variable cost curves of type $(typeof(curve)) are not currently supported. Use a " *
        "CostCurve{LinearCurve} or a FuelCurve{LinearCurve}.",
    )
end

_is_fuel_curve(::PSY.ProductionVariableCostCurve) = false
_is_fuel_curve(::PSY.FuelCurve) = true

has_fuel_curve(d::PSIP.SupplyTechnology) =
    _is_fuel_curve(PSY.get_variable(PSIP.get_operation_costs(d)))

# Fuel consumed per MWh generated
get_heat_rate(fuel_curve::PSY.FuelCurve{PSY.LinearCurve}) =
    PSY.get_proportional_term(PSY.get_value_curve(fuel_curve))

get_heat_rate(fuel_curve::PSY.FuelCurve) = throw_unsupported_curve(fuel_curve)

get_fuel_price(fuel_curve::PSY.FuelCurve) = _get_fuel_price(PSY.get_fuel_cost(fuel_curve))

_get_fuel_price(fuel_price::Float64) = fuel_price

function _get_fuel_price(::IS.TimeSeriesKey)
    error(
        "Time-varying fuel prices are not currently supported. Use a constant fuel price.",
    )
end

# Fuel per MW started (start-up fuel offtake) and per MW committed per hour (no-load term)
get_commitment_fuel(::StartUpCapacityVariable, fuel_curve::PSY.FuelCurve{PSY.LinearCurve}) =
    PSY.get_proportional_term(PSY.get_startup_fuel_offtake(fuel_curve))
get_commitment_fuel(
    ::CommittedCapacityVariable,
    fuel_curve::PSY.FuelCurve{PSY.LinearCurve},
) = PSY.get_constant_term(PSY.get_value_curve(fuel_curve))
