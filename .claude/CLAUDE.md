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

- **`base/`** — core abstractions. `abstract_formulation_types.jl` (`AbstractTechnologyFormulation` → `InvestmentTechnologyFormulation` / `OperationsTechnologyFormulation` / `FeasibilityTechnologyFormulation`); `investment_model_template.jl` (`InvestmentModelTemplate`, `set_technology_model!`); `technology_model.jl` (`TechnologyModel{D,A,B,C}` parameterized by technology type + the three formulations); `transport_model.jl` (`TransportModel{T<:AbstractTransportAggregation}`); `single_optimization_container.jl` (holds `build_model!`) and `multi_optimization_container.jl`; `solution_algorithms.jl` (`SolutionAlgorithm`, `SingleInstanceSolve`, `IterativeMonitoring`); plus `variables.jl`, `constraints.jl`, `expressions.jl`, `objective_function.jl`, `settings.jl`, `time_mapping.jl`, `serialization.jl`, `simulation.jl`, `requirement_model.jl`.
- **`capital/`** — `capital_models.jl` (`CapitalCostModel` → `DiscountedCashFlow`) and `technology_capital_formulations.jl` (investment formulations: `ContinuousInvestment`, `IntegerInvestment`, `BinaryInvestment`, `StaticLoadInvestment`).
- **`operation/`** — `operation_model.jl`, `feasibility_model.jl`, `technology_operation_formulations.jl` (operations formulations: `BasicDispatch`, `BasicDispatchWithBudget`, `BasicDispatchWithLosses`, `ContinuousThermalCommitment`, `ChronologicalStorageDispatch`, `CyclicalStorageDispatch`, colocated variants, `RepresentativePeriods`, `ClusteredRepresentativeDays`).
- **`network_models/`** — `singleregion_model.jl`, `multiregion_model.jl`, `nodal_model.jl`, `ptdf_model.jl`, `transport_constructor.jl` (`construct_transport!`); `network_matrices.jl` (`PTDF` and `LODF`, computed as in PowerNetworkMatrices, which is not a dependency) and `ptdf_network.jl` (the branches of the PTDF network). Transport aggregations: `SingleRegionBalanceModel` / `MultiRegionBalanceModel` (zonal) and `NodalBalanceModel` / `NodalPTDFModel` (nodal, under `AbstractNodalTransportAggregation`). `NodalBalanceModel` is a transport (pipe-flow) balance per node; `NodalPTDFModel` is DC power flow with a PTDF (see below). Balance slacks (`use_slacks`) are implemented for both nodal models.
- **`requirement_models/`** — policy requirements spanning several technologies: `requirement_formulations.jl` (`RequirementEnergyShare`), `requirement_constructor.jl` (`construct_requirements!`), `requirement_utils.jl`, `energy_share_requirement.jl`.
- **`technology_models/`** — `technologies/` per-tech argument/model code (`supply_tech.jl`, `demand_tech.jl`, `storage_tech.jl`, `colocated_tech.jl`, `branch_tech.jl`) plus `common/` (`add_variable.jl`, `add_to_expression.jl`, `objective_function/`); `technology_constructors/` holds the dispatched `construct_technologies!` methods per tech and `constructor_validations.jl`.
- **`investment_model/`** — `investment_model.jl` (`InvestmentModel{S<:SolutionAlgorithm}`, `build!`, `solve!`), `investment_model_store.jl` (`InvestmentModelStore`), `investment_problem_results.jl`.
- **`model_build/`** — `SingleInstanceSolve.jl` (`build_impl!` for the single-instance algorithm) and `IterativeMonitoring.jl` (PTDF only: solve, add the corridors whose exact flow exceeds their limit with `add_monitored_corridors!`, solve again, detaching the solver to add the rows and restoring the previous basis so each solve is warm-started; `get_monitoring_log`, `get_monitored_corridors`).
- **`utils/`** — `jump_utils.jl`, `psip_utils.jl`, `technology_region_utils.jl`, `logging.jl`, `mpi_utils.jl`, and `printing_pt_v2.jl` / `printing_pt_v3.jl` (one is included at load time depending on the installed PrettyTables major version; anything that calls `PrettyTables.pretty_table` with version-specific keywords belongs in both).

## Build flow & public API

1. User builds an `InvestmentModelTemplate(capital_model, operation_model, feasibility_model, transport_model)` and populates it via `set_technology_model!(template, names, Tech, InvFormulation, OpFormulation, FeasFormulation)` and, for policies, `set_requirement_model!(template, names, RequirementType, RequirementFormulation)`.
2. Construct an `InvestmentModel(template, SingleInstanceSolve, portfolio; ...)`.
3. `build!(model; output_dir, ...)` → `build_impl!(::InvestmentModel{SingleInstanceSolve})` (in `model_build/SingleInstanceSolve.jl`) → `build_pre_step!` then `build_model!(container, template, portfolio)` (in `base/single_optimization_container.jl`).
4. `build_model!` initializes system expressions and the transport model's network data (`initialize_network!`, only for `NodalPTDFModel`), builds technology/formulation→name maps, then runs **two ordered passes** — `ArgumentConstructStage()` then `ModelConstructStage()` — calling the dispatched `construct_technologies!` (per tech type + formulation), `construct_requirements!` and `construct_transport!`. Technology and requirement models that share a type and formulation are merged into one name list before construction, and each name keeps the model it was registered with (`names_to_technology_model_map` / `names_to_requirement_model_map`). The feasibility model is only built when feasibility timesteps exist. Within the argument stage the order is technologies, requirements, branches, then `construct_transport!`, so the transport model sees every injection and build variable.
5. `solve!(model; ...)` builds-if-needed, initializes the store, and calls `solve_impl!`.

Public entry points (exports): `InvestmentModel`, `InvestmentModelTemplate`, `TransportModel`, `TechnologyModel`, `RequirementModel`, `set_technology_model!`, `set_requirement_model!`, `get_infeasibility_conflict`, `build!`, `solve!`, `DiscountedCashFlow`, formulation/variable/expression types, and results accessors `get_variable`/`get_constraint`/`get_expression`, `read_variable`/`read_expression`/`read_optimizer_stats`, `serialize_problem`/`serialize_results`, `OptimizationProblemResults`.

## Technology / capital / operation model structure

A `TechnologyModel{D,A,B,C}` couples a `PSIP.Technology` subtype `D` with an investment formulation `A`, an operations formulation `B`, and a feasibility formulation `C`. The template maps these into `technology_models` and `branch_models` dicts; every `PSIP.TransmissionTechnology` goes to `branch_models`. Construction is dispatched on `(tech_type, formulation)` tuples, so adding a technology means adding a `construct_technologies!` method (argument + model stages) and the `add_variable!`/`add_to_expression!`/constraint/objective methods it calls. Mirror an existing technology (e.g. `supply_tech.jl` + `supply_constructor.jl`) when adding a new one.

The investment formulations a technology accepts are listed by `_supported_investment_formulations` at the top of its `*_tech.jl` file and checked when the `TechnologyModel` is constructed: supply and transmission accept continuous, integer and binary; storage continuous and integer; co-located continuous only. `BinaryInvestment` builds at most one unit over the whole horizon (`SingleUnitInvestmentConstraint`). The one-line getters at the top of those files are formulation traits read by the generic code: `get_variable_lower_bound` / `get_variable_upper_bound` (one default per technology, overridden only where data is read), `get_variable_binary` / `get_variable_integer` (decided by the investment formulation), and `get_variable_multiplier` (for build variables, the capacity added by one unit).

## Conventions / gotchas

- Investment models run in **natural units** — `get_problem_base_power` returns `1.0`; there is no per-unit base power.
- Build inputs are a `PSIP.Portfolio`, not a PSY `System`.
- Template model dicts are keyed by the model object (`Dict{TechnologyModel, Vector{String}}`, `Dict{RequirementModel, Vector{String}}`); models are compared by identity, so use the name maps above instead of looking a model up by value.
- Operational weights (`OperationalRepresentativeDays`) are per-year: the weighted duration of each investment period's slices adds up to one year (e.g. `365` for a single representative day). The period length comes from the capital model and is applied when costs are discounted; `check_operational_weights` warns at build time otherwise.
- A `SupplyTechnology` located in more than one region has separate build and dispatch variables per region, indexed as `<name>__<region>` (`get_variable_names` in `utils/technology_region_utils.jl`); `capacity_limits` applies to the total over its regions, and existing capacity or a minimum limit is an error for such a technology. Other technologies must be located in a single region.
- Discrete investment variables count units: capacity and capital cost are scaled by `get_variable_multiplier`, and `get_unit_size` errors on a non-positive unit size.
- A time series that does not start on the first time stamp of its representative period is an error (`check_initial_timestamp`).
- `NodalPTDFModel` (design notes in `.claude/plans/ptdf_design.md`):
  - Terms: a *line* is a `NodalACTransportTechnology` (identified by a `LineKey`); a *corridor* is a node pair; a *branch* is one element (row) of the PTDF: a *merged corridor*, a continuous line on a *new corridor*, or a *unit line* (one unit of a discrete line). `branch_models` in the template is the older, broader use: models of every transmission technology.
  - Lines are grouped into corridors (node pairs). How a `NodalACTransportTechnology` is modeled depends on its investment formulation: continuous lines on a corridor with existing capacity merge into one branch (`MergedCorridor`, susceptance of the existing lines, limit = existing + built capacity); a continuous line on a corridor without existing capacity is a `NewCorridor`; each unit of an integer or binary line is a `UnitLine`. The exact formulations below only exist under this transport model; under the others, discrete line investment only scales capacity by `unit_size`.
  - Branches that may not be built (new corridors and unit lines) get a built binary (`BranchBuiltVariable`) and a virtual transaction (`VirtualTransactionVariable`) that cancels their flow when unbuilt (Rahmani 2016, Mehrtash 2020). This is exact for any set of unbuilt branches. The big-M of each transaction is a shortest path of Fmax / b over existing corridors.
  - Flows are the `PTDFBranchFlow` expression (PTDF × `EnergyBalance` plus the virtual transactions); each island has an `IslandBalanceConstraint`, and branches have `FlowRateConstraint`s. Lines add nothing to `EnergyBalance`, and get no flow variables unless `"flow_variables"` is set.
  - The network data (`PTDFNetworkData`) lives on the `TransportModel`, not the container. Values that need it after the solve (`LineFlow`, the flow of each line technology, sharing a merged corridor's flow by capacity) are computed by `calculate_network_values!`, called from `solve_impl!`.
  - `TransportModel` attributes: `"tol"` (PTDF cutoff for injection terms), `"monitored"` (corridors with flow limits) and `"flow_variables"` (a bounded `FlowActivePowerVariable` per limited branch, set equal to its PTDF flow by `NetworkFlowConstraint`, so the dense flow is written once instead of in both limits).
  - A corridor with nothing to expand (its continuous lines' maximum equals their existing capacity) has a constant limit, applied by one ranged `FlowRateConstraint` (meta `"range"`); limits that depend on built capacity use metas `"lb"` and `"ub"`. Reactance is converted to per unit with the line `voltage`; each island has one reference node (`bus_type == REF`).
- Transport technologies: `BasicDispatch` is lossless (one signed `FlowActivePowerVariable`) and warns when the technology has `line_loss` data. `BasicDispatchWithLosses` (zonal and HVDC links, `ControllableTransportTechnology`) has a flow variable per direction (`FlowActivePowerFromToVariable` / `FlowActivePowerToFromVariable`) sharing the capacity; losses are taken at the receiving end, and the constant term of an HVDC `LinearCurve` (per MW of capacity) is split between both ends. Piecewise losses are not supported, and AC lines are lossless. HVDC links are injections in `EnergyBalance`, so under `NodalPTDFModel` they are not in the PTDF.
- Variable costs dispatch on the parametric curve type of the technology's operation cost: a `PSY.CostCurve{PSY.LinearCurve}` gives the cost per MWh, a `PSY.FuelCurve{PSY.LinearCurve}` gives a heat rate that is priced with its constant fuel price (`common/fuel_curve.jl`); any other curve type goes to `throw_unsupported_curve`. The no-load term of a fuel curve is only used by the commitment formulation. `FuelConsumptionExpression` and `FuelCost` are created only for technologies with a fuel curve.
- Time steps do not have to be hourly. `get_time_step_length(time_mapping, op_ix)` gives the hours per step of a representative period (time stamps must be evenly spaced), and `get_time_step_weight(container, op_ix)` gives the hours of a year each step stands for; use the latter to turn power into annual energy or cost. Representative periods are cyclic: use `get_previous_time_step(time_mapping, op_ix, t)` instead of `t - 1` in inter-temporal constraints.
- `ContinuousThermalCommitment` (thermal supply) relaxes unit commitment to committed, started and shut-down capacity, with minimum up/down times and ramp limits. Its costs come from the technology's `ThermalGenerationCost`, all per MW: `start_up` and `shut_down` on the capacity started and shut down (a staged `start_up` is an error), the fuel curve's `startup_fuel_offtake` per MW started, and its constant (no-load) term per MW committed per hour. Start-up and shut-down terms are per event, so they are weighted by the period weight and not by the step length (`get_cost_weight`).
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

Tests — `test/runtests.jl` uses a `@includetests` macro (TestSetExtensions-style) that auto-discovers `test_*.jl` files (`test_capital_cost.jl`, `test_constructor.jl`, `test_fuel_cost.jl`, `test_model.jl`, `test_multi_region_supply.jl`, `test_network_matrices.jl`, `test_printing.jl`, `test_ptdf_model.jl`, `test_thermal_commitment.jl`, `test_time_steps.jl`, `test_transmission_investment.jl`) and runs Aqua checks; solver is HiGHS. Test deps live in `test/Project.toml`.

```sh
julia --project=test test/runtests.jl                 # full suite
julia --project=test test/runtests.jl test_model      # single file (name without .jl, passed via ARGS)
julia --project=test -e 'using Pkg; Pkg.instantiate()'
```

Docs:

```sh
julia --project=docs docs/make.jl
```
