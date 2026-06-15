# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Run all tests
```julia
julia --project=test test/runtests.jl
```

### Run a specific test file
```julia
# Pass test file names (without .jl) as ARGS via the @includetests macro
julia --project=test -e 'push!(ARGS, "test_model"); include("test/runtests.jl")'
```

### Format code
```julia
julia scripts/formatter/formatter_code.jl
```
The formatter uses JuliaFormatter with settings defined in `scripts/formatter/formatter_code.jl`. Run from the repo root.

### Build docs
```
cd docs && julia --project make.jl
```

## Architecture

PowerSystemsInvestments.jl is a capacity expansion / investment planning optimizer built on JuMP. It sits on top of:
- **PowerSystemsInvestmentsPortfolios.jl** (`PSIP`) — defines the `Portfolio` and `Technology` types that describe what can be built
- **PowerSystems.jl** (`PSY`) — provides the underlying component types (e.g. `ThermalStandard`, `RenewableDispatch`)
- **InfrastructureSystems.jl** (`IS`) / `IS.Optimization` (`ISOPT`) — provides shared optimization infrastructure: container keys, store, results, logging

### Core data flow

```
Portfolio (PSIP)
    └─ InvestmentModelTemplate
           ├─ CapitalCostModel      (e.g. DiscountedCashFlow)
           ├─ OperationCostModel    (e.g. OperationalRepresentativeDays)
           ├─ FeasibilityModel      (e.g. RepresentativePeriods)
           ├─ TransportModel{T}     (SingleRegion / MultiRegion / Nodal)
           └─ TechnologyModel{D,A,B,C}[]
                  D = PSIP.Technology subtype
                  A = InvestmentTechnologyFormulation  (e.g. ContinuousInvestment)
                  B = OperationsTechnologyFormulation  (e.g. BasicDispatch)
                  C = FeasibilityTechnologyFormulation (e.g. BasicDispatchFeasibility)

InvestmentModel{SingleInstanceSolve}(template, alg, portfolio; optimizer=...)
    └─ build!(model; output_dir=...)   → SingleOptimizationContainer (wraps JuMP.Model)
    └─ solve!(model; ...)              → OptimizationProblemResults
```

### Key layers

**`src/base/`** — Core structs and abstractions:
- `abstract_formulation_types.jl` — three abstract formulation axes (`InvestmentTechnologyFormulation`, `OperationsTechnologyFormulation`, `FeasibilityTechnologyFormulation`)
- `technology_model.jl` — `TechnologyModel{D,A,B,C}` combines a technology type with its three formulations
- `investment_model_template.jl` — assembles capital/operation/feasibility/transport models and a dict of `TechnologyModel`s
- `single_optimization_container.jl` — the JuMP-level container holding variables, constraints, expressions, and objective
- `multi_optimization_container.jl` — decomposition container with a main problem + subproblems (MPI-capable)

**`src/investment_model/`** — Top-level model orchestration:
- `investment_model.jl` — `InvestmentModel{S}`, `build!`, `solve!`, `write_results!`
- `investment_model_store.jl` — in-memory result store
- `investment_problem_results.jl` — results interface wrapping the store

**`src/capital/`** — Capital cost models (`DiscountedCashFlow`) and their JuMP formulations

**`src/operation/`** — Operation cost models and dispatch formulations (feasibility variants too)

**`src/network_models/`** — Transport constructors for single-region, multi-region, and nodal balance constraints

**`src/technology_models/`** — Per-technology-type variable/constraint/objective logic:
- `technologies/` — supply, demand, storage, co-located, branch; each calls `add_variable!` / `add_to_expression!` helpers
- `technology_constructors/` — `construct_tech!` methods dispatched on `(TechnologyModel, container, template, portfolio)` that wire the formulations into the container
- `common/objective_function/` — reusable pieces for capital, financial, and operations costs

### Naming conventions
- Module aliases: `IS`, `ISOPT`, `PSY`, `MOI`, `PSIP`, `PM` — defined in `src/PowerSystemsInvestments.jl`
- Container keys are typed structs (`VariableKey`, `ConstraintKey`, `ExpressionKey`) from `ISOPT`
- All optimization variables/expressions are in natural units (base power = 1.0 for investment models)
- `PrettyTables` version is detected at load time; `printing_pt_v2.jl` vs `printing_pt_v3.jl` is selected via `pkgversion`
