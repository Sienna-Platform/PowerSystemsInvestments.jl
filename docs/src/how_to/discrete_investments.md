# [Make Discrete Investment Decisions](@id discrete_investments_how_to)

By default, the capacity built in each investment period can take any value. This guide
shows how to restrict the build decision of a technology to a whole number of units.

It assumes you have a template named `template`. See
[Assign Formulations to Technologies](@ref assign_formulations_how_to).

!!! note
    
    Discrete investment decisions make the problem a mixed-integer program, which requires
    a solver that supports integer variables and can take much longer to solve. Use them
    for the technologies where the unit size is large compared to the system.

## Step 1: Set the unit size of the technology

Set the `unit_size` of the technology, in MW, when defining it in the `Portfolio`:

```julia
nuclear = SupplyTechnology{ThermalStandard}(;
    name="nuclear",
    power_systems_type="ThermalStandard",
    available=true,
    region=[zone],
    capital_costs=LinearCurve(7_000_000.0),
    unit_size=1000.0,
    capacity_limits=(min=0.0, max=4000.0),
    financial_data=financials,
)
```

For a storage technology, set `unit_size_energy`.

## Step 2: Use `IntegerInvestment` for the technology

Assign [`IntegerInvestment`](@ref) as the investment formulation of the technology. Other
technologies of the same type can keep [`ContinuousInvestment`](@ref):

```julia
set_technology_model!(
    template,
    ["nuclear"],
    SupplyTechnology{ThermalStandard},
    IntegerInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
set_technology_model!(
    template,
    ["gas_cc"],
    SupplyTechnology{ThermalStandard},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
```

## Step 3: Read the results

The variables of the two groups are stored under different keys, one for each investment
formulation. With [`IntegerInvestment`](@ref), [`BuildCapacity`](@ref) is the number of
units built in each investment period:

```julia
const PSINV = PowerSystemsInvestments

units_key =
    PSINV.VariableKey(BuildCapacity, SupplyTechnology{ThermalStandard}, "IntegerInvestment")
read_variable(model, units_key)
```

The [`CumulativeCapacity`](@ref) expression is the installed capacity in MW:

```julia
capacity_key = PSINV.ExpressionKey(
    CumulativeCapacity,
    SupplyTechnology{ThermalStandard},
    "IntegerInvestment",
)
read_expression(model, capacity_key)
```

### See also

  - [Supply Technology Formulations](@ref supply_formulations), for the equations of
    [`IntegerInvestment`](@ref) and [`BinaryInvestment`](@ref) and their current
    limitations
