# [Read the Results](@id read_results_how_to)

This guide shows how to find and read the results of a solved [`InvestmentModel`](@ref).
It assumes you have a model named `model` for which [`solve!`](@ref) returned
`SUCCESSFULLY_FINALIZED`.

```julia
using PowerSystemsInvestments
using PowerSystemsInvestmentsPortfolios
using PowerSystems
using DataFrames
const PSINV = PowerSystemsInvestments
```

## List the available results

Results are identified by keys. List the keys of the variables and of the expressions that
were stored:

```julia
collect(PSINV.list_variable_keys(model))
collect(PSINV.list_expression_keys(model))
```

Each key combines the type of the variable or expression, the type of technology it
belongs to, and the name of the formulation that created it.

## Read a variable

Create a `VariableKey` with those three parts and pass it to [`read_variable`](@ref):

```julia
key = PSINV.VariableKey(
    BuildCapacity,
    SupplyTechnology{ThermalStandard},
    "ContinuousInvestment",
)
build = read_variable(model, key)
```

The formulation name is the name of the investment formulation for investment variables,
such as [`BuildCapacity`](@ref), and the name of the operations formulation for operations
variables, such as [`ActivePowerVariable`](@ref).

The result is a `DataFrame` with three columns:

| Column       | Content                                                                                      |
|:------------ |:-------------------------------------------------------------------------------------------- |
| `time_index` | Investment period number for investment variables; time step number for operations variables |
| `name`       | Name of the technology                                                                       |
| `value`      | Value of the variable, in natural units                                                      |

## Read an expression

Create an `ExpressionKey` and pass it to [`read_expression`](@ref):

```julia
key = PSINV.ExpressionKey(
    CumulativeCapacity,
    SupplyTechnology{ThermalStandard},
    "ContinuousInvestment",
)
capacity = read_expression(model, key)
```

The following expressions are stored in the results:

| Expression                                                                                                | Indexed by            | Key                                                 |
|:--------------------------------------------------------------------------------------------------------- |:--------------------- |:--------------------------------------------------- |
| [`CumulativeCapacity`](@ref)                                                                              | Investment period     | Technology type and investment formulation          |
| [`CumulativePowerCapacity`](@ref), [`CumulativeEnergyCapacity`](@ref)                                     | Investment period     | Technology type and investment formulation          |
| [`CumulativeWindCapacity`](@ref), [`CumulativeSolarCapacity`](@ref), [`CumulativeInverterCapacity`](@ref) | Investment period     | Technology type and investment formulation          |
| [`WeightedEnergyGeneration`](@ref)                                                                        | Representative period | Technology type and operations formulation          |
| [`WeightedEnergyDemand`](@ref)                                                                            | Representative period | `Portfolio`, with no formulation name               |
| [`WeightedEnergyShareGeneration`](@ref), [`WeightedEnergyShareDemand`](@ref)                              | Representative period | `EnergyShareRequirements`, with no formulation name |

For the keys without a formulation name, leave it out:

```julia
key = PSINV.ExpressionKey(WeightedEnergyDemand, Portfolio)
demand_energy = read_expression(model, key)
```

In this result, `name` is the name of the region.

## Get the results for one technology

Filter the `DataFrame` by name:

```julia
filter(row -> row.name == "gas_cc", build)
```

## Put technologies in columns

Reshape the result so that each technology is a column:

```julia
unstack(build, :time_index, :name, :value)
```

## Match time steps to time stamps

The time stamps of the operational time steps are stored with the model, in the order of
the `time_index`:

```julia
time_stamps = PSINV.get_time_stamps(model)

dispatch_key = PSINV.VariableKey(
    ActivePowerVariable,
    SupplyTechnology{ThermalStandard},
    "BasicDispatch",
)
dispatch = read_variable(model, dispatch_key)
dispatch.time_stamp = time_stamps[dispatch.time_index]
```

## Calculate the energy produced in an investment period

The [`WeightedEnergyGeneration`](@ref) expression is the energy produced in each
representative period, already multiplied by the weight of the period. Sum it over the
representative periods of an investment period to get the energy produced in MWh:

```julia
key = PSINV.ExpressionKey(
    WeightedEnergyGeneration,
    SupplyTechnology{ThermalStandard},
    "BasicDispatch",
)
energy = read_expression(model, key)
combine(groupby(energy, :name), :value => sum => :energy_mwh)
```

## Read the solver statistics

```julia
read_optimizer_stats(model)
```

## Find the results on disk

[`solve!`](@ref) serializes the results to the output directory that was passed to
[`build!`](@ref). To also export them as files, pass `export_problem_results = true`:

```julia
solve!(model; export_problem_results=true)
```

!!! note
    
    Dual values are not available. See
    [Implementation Status](@ref implementation_status).
