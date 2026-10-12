# [Limit Hydro Energy with a Budget](@id hydro_budget_how_to)

A hydro plant can often produce at full capacity for a few hours but not all day, because
the water available is limited. This guide shows how to limit the energy a hydro technology
produces over each representative period with [`BasicDispatchWithBudget`](@ref).

It assumes you have a `Portfolio` named `portfolio`, a template named `template`, and a
vector of representative periods named `representative_periods`. See
[Define Investment Periods and Representative Days](@ref time_structure_how_to).

```julia
using PowerSystemsInvestments
using PowerSystemsInvestmentsPortfolios
using PowerSystems
using TimeSeries
const PSIP = PowerSystemsInvestmentsPortfolios
```

## Step 1: Define the hydro technology

Define the technology as a `SupplyTechnology{HydroDispatch}`:

```julia
hydro = SupplyTechnology{HydroDispatch}(;
    name="hydro",
    power_systems_type="HydroDispatch",
    available=true,
    region=[zone],
    prime_mover_type=PrimeMovers.HY,
    capital_costs=LinearCurve(2_000_000.0),
    capacity_limits=(min=0.0, max=500.0),
    financial_data=financials,
)
add_technology!(portfolio, hydro)
```

## Step 2: Add the budget time series

The budget is a time series named `"ops_hydro_budget"`, with one value for each time step
of a representative period. The energy the technology can produce over the period is its
installed capacity multiplied by the sum of the series.

To allow the equivalent of 8 hours at full capacity in a 24-hour period, use a constant
value of ``8 / 24``:

```julia
for (rep_day, period) in enumerate(representative_periods)
    budget = fill(8 / 24, length(period))
    time_series = SingleTimeSeries("ops_hydro_budget", TimeArray(period, budget))
    PSIP.add_time_series!(
        portfolio,
        hydro,
        time_series;
        features=Dict("year" => string(year(first(period))), "rep_day" => rep_day),
    )
end
```

Only the sum of the series over the period matters. The values in individual time steps do
not limit the production in those time steps.

## Step 3: Use `BasicDispatchWithBudget` for the technology

Assign [`BasicDispatchWithBudget`](@ref) as the operations formulation:

```julia
set_technology_model!(
    template,
    ["hydro"],
    SupplyTechnology{HydroDispatch},
    ContinuousInvestment,
    BasicDispatchWithBudget,
    BasicDispatchFeasibility,
)
```

With this formulation, the technology can produce up to its installed capacity in any time
step. It does not use a capacity factor time series.

## Step 4: Read the dispatch

The dispatch is stored under the name of the operations formulation:

```julia
const PSINV = PowerSystemsInvestments

dispatch_key = PSINV.VariableKey(
    ActivePowerVariable,
    SupplyTechnology{HydroDispatch},
    "BasicDispatchWithBudget",
)
read_variable(model, dispatch_key)
```

## Limit the production in each time step instead

To limit the production of a hydro technology in each time step with a capacity factor,
as for a wind or solar plant, use [`BasicDispatch`](@ref) and add a time series named
`"ops_variable_cap_factor"` in place of the budget.

### See also

  - [Supply Technology Formulations](@ref supply_formulations)
  - [Time Series Names](@ref time_series_names)
