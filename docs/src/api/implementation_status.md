# [Implementation Status](@id implementation_status)

`PowerSystemsInvestments.jl` is under active development. Some types and options exist in
the API before the behavior behind them is implemented. This page lists what is available
today.

## Template models

| Component             | Available                                                                                          | Not implemented                                                         |
|:--------------------- |:-------------------------------------------------------------------------------------------------- |:----------------------------------------------------------------------- |
| Solution algorithm    | [`SingleInstanceSolve`](@ref)                                                                      | Decomposition algorithms                                                |
| Capital cost model    | [`DiscountedCashFlow`](@ref)                                                                       |                                                                         |
| Operation cost model  | [`OperationalRepresentativeDays`](@ref)                                                            | [`AggregateOperatingCost`](@ref), [`ClusteredRepresentativeDays`](@ref) |
| Feasibility model     | [`RepresentativePeriods`](@ref) with no periods                                                    | [`RepresentativePeriods`](@ref) with periods; see below                 |
| Transport formulation | [`SingleRegionBalanceModel`](@ref), [`MultiRegionBalanceModel`](@ref), [`NodalBalanceModel`](@ref) | Power flow constraints                                                  |

See the [Formulation Library](@ref formulation_library_intro) for the technology and
requirement formulations that are available.

## Feasibility periods

A template requires a feasibility model and every [`TechnologyModel`](@ref) requires a
feasibility formulation, but feasibility periods are only partly implemented. Supply,
storage, and demand technologies contribute to a `FeasibilitySurplus` expression, and a
constraint on that expression is added only with a [`SingleRegionBalanceModel`](@ref).
Feasibility-specific variables and constraints are not created for any technology.

Use `RepresentativePeriods(Vector{Vector{DateTime}}())` to build a model without
feasibility periods.

## Options that are accepted but not used

| Option                                                                                          | Status                                               |
|:----------------------------------------------------------------------------------------------- |:---------------------------------------------------- |
| `use_slacks` in [`TransportModel`](@ref), [`TechnologyModel`](@ref), [`RequirementModel`](@ref) | No slack variables are created                       |
| `duals` in [`TechnologyModel`](@ref) and [`RequirementModel`](@ref)                             | No dual values are stored                            |
| `discount_rate` and `base_year` of [`DiscountedCashFlow`](@ref)                                 | The values of the `Portfolio` are used instead       |
| `horizon`, `resolution`, `initial_time` of [`InvestmentModel`](@ref)                            | Not used; the time structure comes from the template |

## `Portfolio` data that is not used

The following fields of the technologies in a `Portfolio` do not affect the model:

  - `outage_factor`, `min_generation_fraction`, `ramp_limits`, `time_limits`, and
    `lifetime` of supply technologies
  - `losses`, `duration_limits`, and the charge-specific capacity and cost fields of
    storage technologies
  - `value_of_lost_load` and `unserved_demand_curve` of demand technologies
  - Time series named `"inv_capex"`
  - Requirements other than `EnergyShareRequirements`

Only the proportional term of each cost curve is used.

## Not modeled

  - Retirement of existing capacity
  - Unserved demand
  - Unit commitment, ramping, and minimum generation
  - Reserve and capacity adequacy requirements
  - Emissions
