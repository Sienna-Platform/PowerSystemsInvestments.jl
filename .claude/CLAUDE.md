# PowerSystemsInvestments.jl — Claude Guide

Platform-wide Sienna conventions (performance, type stability, formatter, environments, code style) live in `.claude/Sienna.md` — read it too. This file is repo-specific and does not restate them.

## Purpose & place in the stack

PowerSystemsInvestments (PSINV / `PowerSystemsInvestments`) is the Sienna library for power-systems **investment** models — capacity expansion and transmission expansion. It builds JuMP optimization problems over an investment horizon (plus nested operational/feasibility periods) and solves them via MathOptInterface.

Verified deps (`Project.toml`):

- **InfrastructureSystems** (`IS`, compat `2`) — supplies the optimization layer used here as `IS.Optimization` (aliased `ISOPT`): `OptimizationContainerKey`, `VariableKey`/`ConstraintKey`/`ExpressionKey`, construct stages, store containers, `OptimizationProblemResults`, logging. There is **no** `InfrastructureOptimizationModels`/`IOM` dependency — the seed context file claimed one; it is stale. The generic optimization machinery comes from `IS.Optimization`.
- **PowerSystemsInvestmentsPortfolios** (`PSIP`, compat `0.1`) — the data model consumed by this package: `PSIP.Portfolio`, `PSIP.Technology` (candidate technologies, investment options). Build inputs are a `Portfolio`, not a `System`.
- **PowerSystems** (`PSY`, compat `4`) — core component data model; mostly used for accessors (`PSY.get_name`).
- **JuMP** (`1`), **MathOptInterface** (`1`) — model construction / solver interface.
- **PowerNetworkMatrices** (`PNM`, `^0.11`), **PowerModels** (`PM`, `^0.21`) — network representation for transmission models.
- Support: DataFrames, DataStructures, TimeSeries, PrettyTables, JSON3, Serialization, TimerOutputs, DocStringExtensions, Logging, Dates.

Julia compat: `^1.6`. Upstream: IS, PSY, PSIP, PNM/PM. Downstream: end-user expansion-planning workflows.

## Architecture & src/ layout

Single module `src/PowerSystemsInvestments.jl` lists all exports/imports and the (order-sensitive) include list. Directories under `src/`:

- **`base/`** — core abstractions. `abstract_formulation_types.jl` (`AbstractTechnologyFormulation` → `InvestmentTechnologyFormulation` / `OperationsTechnologyFormulation` / `FeasibilityTechnologyFormulation`); `investment_model_template.jl` (`InvestmentModelTemplate`, `set_technology_model!`); `technology_model.jl` (`TechnologyModel{D,A,B,C}` parameterized by technology type + the three formulations); `transport_model.jl` (`TransportModel{T<:AbstractTransportAggregation}`); `single_optimization_container.jl` (holds `build_model!`) and `multi_optimization_container.jl`; `solution_algorithms.jl` (`SolutionAlgorithm`, `SingleInstanceSolve`); plus `variables.jl`, `constraints.jl`, `expressions.jl`, `objective_function.jl`, `settings.jl`, `time_mapping.jl`, `serialization.jl`, `simulation.jl`, `requirement_model.jl`.
- **`capital/`** — `capital_models.jl` (`CapitalCostModel` → `DiscountedCashFlow`) and `technology_capital_formulations.jl` (investment formulations: `ContinuousInvestment`, `IntegerInvestment`, `StaticLoadInvestment`).
- **`operation/`** — `operation_model.jl`, `feasibility_model.jl`, `technology_operation_formulations.jl` (operations formulations: `BasicDispatch`, `ChronologicalStorageDispatch`, `CyclicalStorageDispatch`, colocated variants, `RepresentativePeriods`, `ClusteredRepresentativeDays`).
- **`network_models/`** — `singleregion_model.jl`, `multiregion_model.jl`, `transport_constructor.jl` (`construct_transport!`); transport aggregations `SingleRegionBalanceModel` / `MultiRegionBalanceModel`.
- **`technology_models/`** — `technologies/` per-tech argument/model code (`supply_tech.jl`, `demand_tech.jl`, `storage_tech.jl`, `colocated_tech.jl`, `branch_tech.jl`) plus `common/` (`add_variable.jl`, `add_to_expression.jl`, `objective_function/`); `technology_constructors/` holds the dispatched `construct_technologies!` methods per tech and `constructor_validations.jl`.
- **`investment_model/`** — `investment_model.jl` (`InvestmentModel{S<:SolutionAlgorithm}`, `build!`, `solve!`), `investment_model_store.jl` (`InvestmentModelStore`), `investment_problem_results.jl`.
- **`model_build/`** — `SingleInstanceSolve.jl` (`build_impl!` for the single-instance algorithm).
- **`utils/`** — `jump_utils.jl`, `psip_utils.jl`, `printing.jl`, `logging.jl`, `mpi_utils.jl`.

## Build flow & public API

1. User builds an `InvestmentModelTemplate(transport_aggregation)`, populates it via `set_technology_model!(template, TechnologyModel{Tech, InvFormulation, OpFormulation, FeasFormulation}(...))`, and sets the capital / operation / feasibility / transport models.
2. Construct an `InvestmentModel(SingleInstanceSolve, template, portfolio; ...)`.
3. `build!(model; output_dir, ...)` → `build_impl!(::InvestmentModel{SingleInstanceSolve})` (in `model_build/SingleInstanceSolve.jl`) → `build_pre_step!` then `build_model!(container, template, portfolio)` (in `base/single_optimization_container.jl`).
4. `build_model!` initializes system expressions, builds technology/formulation→name maps, then runs **two ordered passes** — `ArgumentConstructStage()` then `ModelConstructStage()` — calling the dispatched `construct_technologies!` (per tech type + formulation) and `construct_transport!`. The feasibility model is only built when feasibility timesteps exist.
5. `solve!(model; ...)` builds-if-needed, initializes the store, and calls `solve_impl!`.

Public entry points (exports): `InvestmentModel`, `InvestmentModelTemplate`, `TransportModel`, `TechnologyModel`, `set_technology_model!`, `build!`, `solve!`, `DiscountedCashFlow`, formulation/variable/expression types, and results accessors `get_variable`/`get_constraint`/`get_expression`, `read_variable`/`read_expression`/`read_optimizer_stats`, `serialize_problem`/`serialize_results`, `OptimizationProblemResults`.

## Technology / capital / operation model structure

A `TechnologyModel{D,A,B,C}` couples a `PSIP.Technology` subtype `D` with an investment formulation `A`, an operations formulation `B`, and a feasibility formulation `C`. The template maps these into `technology_models` and `branch_models` dicts. Construction is dispatched on `(tech_type, formulation)` tuples, so adding a technology means adding a `construct_technologies!` method (argument + model stages) and the `add_variable!`/`add_to_expression!`/constraint/objective methods it calls. Mirror an existing technology (e.g. `supply_tech.jl` + `supply_constructor.jl`) when adding a new one.

## Conventions / gotchas

- Investment models run in **natural units** — `get_problem_base_power` returns `1.0`; there is no per-unit base power.
- Build inputs are a `PSIP.Portfolio`, not a PSY `System`.
- Several template fields and dict value types are still loosely typed (`technology_models::Dict` with a `# TODO` for a strict type) — do not assume concrete element types.
- Respect the include order in `src/PowerSystemsInvestments.jl`: abstract formulation types, capital/operation/transport, then containers, then technology constructors. New types must be defined before files that reference them.

## Optimization Model Construction Conventions

### `add_*!()` methods must not return collections
Methods that create variables, constraints, or expressions (`add_variables!`, `add_constraints!`, `add_expressions!`, etc.) must always end with a bare `return` (i.e., return `nothing`). They must never return dicts or collections of JuMP objects. Instead, instantiate the appropriate container via `add_*_container!` and store all created objects there.

### Inline expressions when possible
Expression construction should be inlined at the point of use. Only store an expression in a container when it is intended to be reused across multiple constraints or objective terms. Avoid creating expression containers solely as intermediate computation steps.

(Verified: `add_variable!` and `add_to_expression!` in `src/technology_models/technologies/common/` end with a bare `return` after storing into containers via `add_variable_container!` / `get_expression`.)

## Cross-package coupling

- The optimization-container key types, construct stages, store containers, and results interfaces are **imported from `IS.Optimization`** — push changes upstream into InfrastructureSystems rather than re-implementing them here.
- Data structures (`Portfolio`, `Technology` and their accessors) live in PowerSystemsInvestmentsPortfolios; do not add data-model fields here.
- Network/transport math relies on PowerNetworkMatrices and PowerModels.

## Running tests, docs, formatter (verified commands)

Formatter (self-activates its own environment):

```sh
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
```

Tests — `test/runtests.jl` uses a `@includetests` macro (TestSetExtensions-style) that auto-discovers `test_*.jl` files (`test_constructor.jl`, `test_model.jl`) and runs Aqua checks; solver is HiGHS. Test deps live in `test/Project.toml`.

```sh
julia --project=test test/runtests.jl                 # full suite
julia --project=test test/runtests.jl test_model      # single file (name without .jl, passed via ARGS)
julia --project=test -e 'using Pkg; Pkg.instantiate()'
```

Docs:

```sh
julia --project=docs docs/make.jl
```
