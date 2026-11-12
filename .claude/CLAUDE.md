# PowerSystemsInvestments.jl — Claude Guide

Platform-wide Sienna conventions (performance, type stability, formatter, environments, code style) live in `.claude/Sienna.md` — read it too. This file is repo-specific and does not restate them.

## Purpose & place in the stack

PowerSystemsInvestments (PSINV / `PowerSystemsInvestments`) is the Sienna library for power-systems **investment** models — capacity expansion and transmission expansion. It builds JuMP optimization problems over an investment horizon (plus nested operational/feasibility periods) and solves them via MathOptInterface.

Verified deps (`Project.toml`):

- **InfrastructureSystems** (`IS`, compat `3.6.3`) — supplies the optimization layer used here as `IS.Optimization` (aliased `ISOPT`): `OptimizationContainerKey`, `VariableKey`/`ConstraintKey`/`ExpressionKey`, construct stages, store containers, `OptimizationProblemResults`, logging. There is **no** `InfrastructureOptimizationModels`/`IOM` dependency — the seed context file claimed one; it is stale. The generic optimization machinery comes from `IS.Optimization`.
- **PowerSystemsInvestmentsPortfolios** (`PSIP`, compat `0.1.0`) — the data model consumed by this package: `PSIP.Portfolio`, `PSIP.Technology` (candidate technologies, investment options). Build inputs are a `Portfolio`, not a `System`.
- **PowerSystems** (`PSY`, compat `5.12.3`) — core component data model; mostly used for accessors (`PSY.get_name`).
- **JuMP** (`1`), **MathOptInterface** (`1`) — model construction / solver interface.
- **PowerModels** (`PM`, `^0.21`) — network representation for transmission models. PowerNetworkMatrices is no longer a dependency.
- Support: DataFrames, DataStructures, TimeSeries, PrettyTables (`2, 3`), JSON3, Serialization, TimerOutputs, DocStringExtensions, Logging, Dates.

Julia compat: `^1.10`. Upstream: IS, PSY, PSIP, PM. Downstream: end-user expansion-planning workflows.

## Architecture & src/ layout

Single module `src/PowerSystemsInvestments.jl` lists all exports/imports and the (order-sensitive) include list. Directories under `src/`:

- **`base/`** — core abstractions. `abstract_formulation_types.jl` (`AbstractTechnologyFormulation` → `InvestmentTechnologyFormulation` / `OperationsTechnologyFormulation` / `FeasibilityTechnologyFormulation`); `investment_model_template.jl` (`InvestmentModelTemplate`, `set_technology_model!`); `technology_model.jl` (`TechnologyModel{D,A,B,C}` parameterized by technology type + the three formulations); `transport_model.jl` (`TransportModel{T<:AbstractTransportAggregation}`); `single_optimization_container.jl` (holds `build_model!`) and `multi_optimization_container.jl`; `solution_algorithms.jl` (`SolutionAlgorithm`, `SingleInstanceSolve`); plus `variables.jl`, `constraints.jl`, `expressions.jl`, `objective_function.jl`, `settings.jl`, `time_mapping.jl`, `serialization.jl`, `simulation.jl`, `requirement_model.jl`.
- **`capital/`** — `capital_models.jl` (`CapitalCostModel` → `DiscountedCashFlow`) and `technology_capital_formulations.jl` (investment formulations: `ContinuousInvestment`, `IntegerInvestment`, `BinaryInvestment`, `StaticLoadInvestment`).
- **`operation/`** — `operation_model.jl`, `feasibility_model.jl`, `technology_operation_formulations.jl` (operations formulations: `BasicDispatch`, `BasicDispatchWithBudget`, `ChronologicalStorageDispatch`, `CyclicalStorageDispatch`, colocated variants, `RepresentativePeriods`, `ClusteredRepresentativeDays`).
- **`network_models/`** — `singleregion_model.jl`, `multiregion_model.jl`, `nodal_model.jl`, `transport_constructor.jl` (`construct_transport!`); transport aggregations `SingleRegionBalanceModel` / `MultiRegionBalanceModel` / `NodalBalanceModel`. The nodal model is a transport (pipe-flow) balance per node; balance slacks (`use_slacks`) are only implemented for it.
- **`requirement_models/`** — policy requirements spanning several technologies: `requirement_formulations.jl` (`RequirementEnergyShare`), `requirement_constructor.jl` (`construct_requirements!`), `requirement_utils.jl`, `energy_share_requirement.jl`.
- **`technology_models/`** — `technologies/` per-tech argument/model code (`supply_tech.jl`, `demand_tech.jl`, `storage_tech.jl`, `colocated_tech.jl`, `branch_tech.jl`) plus `common/` (`add_variable.jl`, `add_to_expression.jl`, `objective_function/`); `technology_constructors/` holds the dispatched `construct_technologies!` methods per tech and `constructor_validations.jl`.
- **`investment_model/`** — `investment_model.jl` (`InvestmentModel{S<:SolutionAlgorithm}`, `build!`, `solve!`), `investment_model_store.jl` (`InvestmentModelStore`), `investment_problem_results.jl`.
- **`model_build/`** — `SingleInstanceSolve.jl` (`build_impl!` for the single-instance algorithm).
- **`utils/`** — `jump_utils.jl`, `psip_utils.jl`, `technology_region_utils.jl`, `logging.jl`, `mpi_utils.jl`, and `printing_pt_v2.jl` / `printing_pt_v3.jl` (one is included at load time depending on the installed PrettyTables major version; anything that calls `PrettyTables.pretty_table` with version-specific keywords belongs in both).

## Build flow & public API

1. User builds an `InvestmentModelTemplate(capital_model, operation_model, feasibility_model, transport_model)` and populates it via `set_technology_model!(template, names, Tech, InvFormulation, OpFormulation, FeasFormulation)` and, for policies, `set_requirement_model!(template, names, RequirementType, RequirementFormulation)`.
2. Construct an `InvestmentModel(template, SingleInstanceSolve, portfolio; ...)`.
3. `build!(model; output_dir, ...)` → `build_impl!(::InvestmentModel{SingleInstanceSolve})` (in `model_build/SingleInstanceSolve.jl`) → `build_pre_step!` then `build_model!(container, template, portfolio)` (in `base/single_optimization_container.jl`).
4. `build_model!` initializes system expressions, builds technology/formulation→name maps, then runs **two ordered passes** — `ArgumentConstructStage()` then `ModelConstructStage()` — calling the dispatched `construct_technologies!` (per tech type + formulation), `construct_requirements!` and `construct_transport!`. Technology and requirement models that share a type and formulation are merged into one name list before construction, and each name keeps the model it was registered with (`names_to_technology_model_map` / `names_to_requirement_model_map`). The feasibility model is only built when feasibility timesteps exist.
5. `solve!(model; ...)` builds-if-needed, initializes the store, and calls `solve_impl!`.

Public entry points (exports): `InvestmentModel`, `InvestmentModelTemplate`, `TransportModel`, `TechnologyModel`, `RequirementModel`, `set_technology_model!`, `set_requirement_model!`, `get_infeasibility_conflict`, `build!`, `solve!`, `DiscountedCashFlow`, formulation/variable/expression types, and results accessors `get_variable`/`get_constraint`/`get_expression`, `read_variable`/`read_expression`/`read_optimizer_stats`, `serialize_problem`/`serialize_results`, `OptimizationProblemResults`.

## Technology / capital / operation model structure

A `TechnologyModel{D,A,B,C}` couples a `PSIP.Technology` subtype `D` with an investment formulation `A`, an operations formulation `B`, and a feasibility formulation `C`. The template maps these into `technology_models` and `branch_models` dicts. Construction is dispatched on `(tech_type, formulation)` tuples, so adding a technology means adding a `construct_technologies!` method (argument + model stages) and the `add_variable!`/`add_to_expression!`/constraint/objective methods it calls. Mirror an existing technology (e.g. `supply_tech.jl` + `supply_constructor.jl`) when adding a new one.

The investment formulations a technology accepts are listed by `_supported_investment_formulations` at the top of its `*_tech.jl` file and checked when the `TechnologyModel` is constructed: supply accepts continuous, integer and binary; storage continuous and integer; co-located and branches continuous only. The one-line getters at the top of those files are formulation traits read by the generic code: `get_variable_lower_bound` / `get_variable_upper_bound` (one default per technology, overridden only where data is read), `get_variable_binary` / `get_variable_integer` (decided by the investment formulation), and `get_variable_multiplier` (for build variables, the capacity added by one unit).

## Conventions / gotchas

- Investment models run in **natural units** — `get_problem_base_power` returns `1.0`; there is no per-unit base power.
- Build inputs are a `PSIP.Portfolio`, not a PSY `System`.
- Template model dicts are keyed by the model object (`Dict{TechnologyModel, Vector{String}}`, `Dict{RequirementModel, Vector{String}}`); models are compared by identity, so use the name maps above instead of looking a model up by value.
- Operational weights (`OperationalRepresentativeDays`) are per-year: the weighted duration of each investment period's slices adds up to one year (e.g. `365` for a single representative day). The period length comes from the capital model and is applied when costs are discounted; `check_operational_weights` warns at build time otherwise.
- A `SupplyTechnology` located in more than one region has separate build and dispatch variables per region, indexed as `<name>__<region>` (`get_variable_names` in `utils/technology_region_utils.jl`); `capacity_limits` applies to the total over its regions, and existing capacity or a minimum limit is an error for such a technology. Other technologies must be located in a single region.
- Discrete investment variables count units: capacity and capital cost are scaled by `get_variable_multiplier`, and `get_unit_size` errors on a non-positive unit size.
- A time series that does not start on the first time stamp of its representative period is an error (`check_initial_timestamp`).
- The base year and discount rate used in the objective come from the `Portfolio`; `DiscountedCashFlow` only supplies the investment periods.
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
- Network/transport math relies on PowerModels.

## Running tests, docs, formatter (verified commands)

Formatter (self-activates its own environment):

```sh
julia --project=scripts/formatter -e 'include("scripts/formatter/formatter_code.jl")'
```

Tests — `test/runtests.jl` uses a `@includetests` macro (TestSetExtensions-style) that auto-discovers `test_*.jl` files (`test_capital_cost.jl`, `test_constructor.jl`, `test_model.jl`, `test_multi_region_supply.jl`, `test_printing.jl`) and runs Aqua checks; solver is HiGHS. Test deps live in `test/Project.toml`.

```sh
julia --project=test test/runtests.jl                 # full suite
julia --project=test test/runtests.jl test_model      # single file (name without .jl, passed via ARGS)
julia --project=test -e 'using Pkg; Pkg.instantiate()'
```

Docs:

```sh
julia --project=docs docs/make.jl
```
