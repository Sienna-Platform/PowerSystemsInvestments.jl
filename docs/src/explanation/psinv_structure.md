# [Package Structure](@id psinv_structure)

`PowerSystemsInvestments.jl` turns a description of a planning problem into an optimization
problem, solves it, and returns the results. This page explains the pieces involved and why
they are separate.

## Data and modeling choices are separate

A capacity expansion study mixes two kinds of information. Some of it is *data*: which
technologies could be built, what they cost, where they are, and how demand and resource
availability vary over time. The rest is *modeling choices*: whether build decisions are
continuous or come in whole units, how many regions are represented, which days stand in
for a year of operation, and how storage is tracked between those days.

`PowerSystemsInvestments.jl` keeps the two apart:

  - The data lives in a `Portfolio`, defined with
    [`PowerSystemsInvestmentsPortfolios.jl`](https://sienna-platform.github.io/PowerSystemsInvestmentsPortfolios.jl/stable/)
  - The modeling choices live in an [`InvestmentModelTemplate`](@ref), defined in this
    package

The same separation is used for operations problems in
[`PowerSimulations.jl`](https://sienna-platform.github.io/PowerSimulations.jl/stable/),
where a `System` holds the data and a `ProblemTemplate` holds the choices. The benefit is
the same in both: a modeling choice can be changed and the problem solved again without
touching the data, which makes it practical to test how much a simplification changes the
answer.

## The pieces

```
Portfolio                         the data
   │
   │      InvestmentModelTemplate            the modeling choices
   │         ├─ capital cost model           when capacity can be built, how it is paid for
   │         ├─ operation cost model         which periods represent operation
   │         ├─ feasibility model            which periods test the plan
   │         ├─ transport model              how energy balances are aggregated
   │         ├─ technology models            formulations for each technology
   │         └─ requirement models           formulations for each policy
   │              │
   ▼              ▼
InvestmentModel                   data + choices + a solution algorithm
   │
   │  build!                      creates the JuMP optimization problem
   │  solve!                      solves it and stores the results
   ▼
results                           variables and expressions, as DataFrames
```

### The `Portfolio`

A `Portfolio` contains technologies, regions, requirements, time series, and financial
assumptions. Technologies are parameterized by a
[`PowerSystems.jl`](https://sienna-platform.github.io/PowerSystems.jl/stable/) component
type, for example `SupplyTechnology{ThermalStandard}` or
`StorageTechnology{EnergyReservoirStorage}`. That parameter says what kind of equipment the
technology is, and `PowerSystemsInvestments.jl` uses it to decide which equations apply. A
`SupplyTechnology{RenewableDispatch}` is limited by a capacity factor time series; a
`SupplyTechnology{ThermalStandard}` is not.

### The template

An [`InvestmentModelTemplate`](@ref) has four models that apply to the whole problem and
two collections of models that apply to parts of it:

  - A capital cost model, such as [`DiscountedCashFlow`](@ref), which defines the
    investment periods
  - An operation cost model, such as [`OperationalRepresentativeDays`](@ref), which defines
    the periods used to represent operation
  - A feasibility model, such as [`RepresentativePeriods`](@ref), which defines additional
    periods used to test the investment plan
  - A [`TransportModel`](@ref), which defines whether supply and demand are balanced for
    the whole portfolio, for each zone, or for each node
  - A [`TechnologyModel`](@ref) for each group of technologies, which names the
    formulations used for their investment, operation, and feasibility. See
    [Formulations](@ref formulation_axes).
  - A [`RequirementModel`](@ref) for each policy that spans several technologies, such as
    an energy share requirement

### The `InvestmentModel`

An [`InvestmentModel`](@ref) combines a template and a `Portfolio` with a
[`SolutionAlgorithm`](@ref) and the settings for the solver. The solution algorithm is a
type parameter of the model. [`SingleInstanceSolve`](@ref), the only algorithm available
today, formulates the whole problem as a single optimization problem. The parameter exists
so that decomposition algorithms, which split the problem into a main problem and
subproblems, can be added without changing how a model is defined.

[`build!`](@ref) creates the optimization problem and [`solve!`](@ref) solves it. See
[How a Model is Built](@ref build_process) for what happens in between.

## Where the code comes from

`PowerSystemsInvestments.jl` sits on top of several other Sienna packages and adds only
what is specific to investment problems:

| Package                                | What it provides                                                                                                      |
|:-------------------------------------- |:--------------------------------------------------------------------------------------------------------------------- |
| `PowerSystems.jl`                      | Component types used as technology parameters, cost curves, and time series types                                     |
| `PowerSystemsInvestmentsPortfolios.jl` | The `Portfolio`, technology, region, and requirement types                                                            |
| `InfrastructureSystems.jl`             | Time series storage, units, logging, and the abstract types for variables, constraints, and expressions               |
| `InfrastructureOptimizationModels.jl`  | The optimization container keys, the result store, and the results object, shared with other Sienna modeling packages |
| `JuMP.jl`                              | The algebraic modeling layer and the interface to solvers                                                             |
| `PowerSystemsInvestments.jl`           | The template, the formulations, and the equations of the investment problem                                           |

Because the result store and the keys are shared with the operations packages, results from
an investment model are read the same way as results from an operations model.

## Units

Everything in an investment model is in natural units: MW for power, MWh for energy, and
dollars for costs. There is no per-unit system and no base power. This follows
`PowerSystemsInvestmentsPortfolios.jl`, which stores all quantities in natural units, and
it means that the values read from the results are directly comparable to the values in the
`Portfolio`.
