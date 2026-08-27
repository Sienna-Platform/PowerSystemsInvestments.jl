# IOM ⇄ PSIN Consolidation Analysis

Comparison of **InfrastructureOptimizationModels.jl (IOM)** and **PowerSystemsInvestments.jl (PSIN)**
to identify what PSIN can reuse from / move into IOM, or remove as redundant.

> **Provenance / status:** Captured on the `jp/iom_integration` (PSIN) / `jp/invest_integration` (IOM)
> branches, *before* the PSIN↔IOM integration work that took the suite to 79/79. Several items have
> since been partially addressed during that integration — those are flagged inline with _(status: …)_.
> The byte-identical duplicates (Tier A) and forwarders (Tier B) are high-confidence; the cost-curve
> overlap (Tier D.2) and store consolidation (Tier C.2) are inferences to confirm against IOM
> signatures before deleting.

---

## Part 1 — What IOM provides

IOM is essentially the extracted PowerSimulations core: a generic JuMP optimization framework with
no power-flow / domain semantics of its own.

| Area | IOM provides (file) |
|---|---|
| **Container + keys** | `OptimizationContainer`, all key types (`VariableKey`/`ConstraintKey`/`ExpressionKey`/`AuxVarKey`/`ParameterKey`/`InitialConditionKey`), `OptimizationContainerMetadata`, full CRUD API (`add_*_container!`, `get_*`, `has_container_key`, `list_keys`), the `@generated` `field_for_type`/`store_field_for_type` dispatch, encode/decode key helpers (`src/core/optimization_container*.jl`) |
| **Objective** | `ObjectiveFunction` (invariant/variant split), cost-term helpers (`add_cost_term_invariant!/variant!`, `add_proportional_cost_invariant!`), full cost-curve→objective pipeline for `IS.LinearCurve`/`QuadraticCurve`/`PiecewisePointCurve`/`CostCurve`/`FuelCurve` incl. PWL lambda & delta (`src/objective_function/`) |
| **Model internal/store** | `ModelInternal`, `ModelStoreParams`, `AbstractModelStore` (+ `DecisionModelStore`/`EmulationModelStore`), status/logging/recorders/output-dir plumbing (`src/core/model_internal.jl`, `abstract_model_store.jl`) |
| **Results** | `OptimizationProblemOutputs` (+`Export`), read/export/serialize/list/to_dataframe machinery, natural-units handling, LONG/WIDE table formatting (`src/core/optimization_problem_outputs.jl`) |
| **Settings** | `Settings` with full getter/setter API (horizon/resolution/optimizer/conflict/etc.) (`src/core/settings.jl`) |
| **Model lifecycle** | `AbstractOptimizationModel`/`DecisionModel`/`EmulationModel`, `solve_model!`, `execute_optimizer!`, `compute_conflict!`, `init_optimization_container!`, `AbstractProblemTemplate` interface, `DeviceModel{D,B}`/`ServiceModel{D,B}`. Top-level `build!`/`solve!` are intentionally left to downstream. |
| **JuMP utils** | `jump_value`, `to_matrix`, `to_dataframe`, `to_outputs_dataframe`, `container_spec`/`sparse_container_spec`, `remove_undef!`, `write_optimizer_stats!`, `serialize_jump_optimization_model`, `check_conflict_status`, `supports_milp` (`src/utils/jump_utils.jl`) |
| **Generic constraint libs** | range/ramp/duration/semicontinuous constraint builders (`src/common_models/constraint_helpers.jl`, `range_constraint.jl`, `duration_constraints.jl`) |
| **Approximations** | bilinear (McCormick/NMDT) and quadratic/PWL (SOS2/sawtooth/epigraph) libraries |
| **Investment abstractions (already exported)** | `InvestmentVariableType`, `OperationsVariableType`, `FeasibilityVariableType`, `BuildInvestmentVariableType`, `InvestmentExpressionType`, `OperationsExpressionType`, `FeasibilityExpressionType`, `CumulativeInvestmentExpressionType` — plus a near-empty `src/investments/` stub, clearly the intended home for PSIN's investment layer |

---

## Part 2 — Recommendations (move / remove / keep)

### Tier A — Delete outright; reuse IOM directly (high confidence, low risk)
Near-duplicates, several byte-identical:

1. (DONE) **`src/utils/jump_utils.jl` — delete nearly the whole file.** `jump_value`, `add_jump_parameter`,
   `fix_parameter_value`, `to_matrix` (dense+sparse), `container_spec`/`sparse_container_spec`,
   `remove_undef!` (byte-identical), `supports_milp`, `write_optimizer_stats!`,
   `serialize_jump_optimization_model`, `check_conflict_status` all exist in IOM.
   _(status: partly done — the local `supports_milp` override was removed during integration.)_
   Double-check only `write_data` (good to delete) / `get_column_names`(port additional defs to IOM) / `encode_tuple_to_column` (identical can delete) for divergence
   before deleting.
2. (remove pt_v2, partially ported pt_v3, maybe revisit) **`printing_pt_v3.jl` / `printing_pt_v2.jl`** — `tf_html_simple` CSS is byte-identical to IOM's
   `print_pt_v3.jl`; `_show_method(::OptimizationProblemOutputs)` is a near-clone (IOM's is a
   superset). Delete the duplicated results-printing; keep only PSIN-specific `show`
   (InvestmentModel / template).
3. (DONE) **Redundant container helpers in `single_optimization_container.jl`** — `_add_to_jump_expression!`
   family duplicates IOM's `add_constant/proportional_to_jump_expression!`; `_assign_container!`
   duplicates IOM's. Import from IOM instead.

### Tier B — Collapse thin forwarders (low risk)
Blocks of 1-line `IOM.get_X`/`set_X!` forwards. Replace hand-written forwarders with
`import InfrastructureOptimizationModels: <names>`, keeping only genuine renames:

- (DONE) `settings.jl` (~18 forwarders) — keep only `InvestmentSettings` + the `get_portfolio_to_file` rename.
- (DONE) `single_optimization_container.jl` container getters.
  _(status: DONE — these were removed and imported from IOM; this fixed the `StackOverflowError`
  from the self-recursive `get_optimizer_stats` forwarder and the `get_objective_expression(::ObjectiveFunction)`
  shadowing.)_
- (Porting the entire investment model and investment model store over to IOM)`investment_model.jl` lifecycle getters / level setters / `list_*_keys`.
- `objective_function.jl` — keep only the `get_capital_terms` / `get_operation_terms` semantic renames.

> **Gotcha (learned the hard way):** if a name is imported from IOM, do **not** also define
> `name(container) = IOM.name(container)` — that overwrites IOM's real method with a self-call
> (StackOverflow). Import xor forward; never both.

### Tier C — Consolidate, but investigate first (medium risk — code has drifted)
1. **`solve_model!` / `compute_conflict!`** are copies of IOM's `execute_optimizer!` /
   `compute_conflict!` — PSIN's `compute_conflict!` had regressed (missing IOM's per-constraint
   `try` hardening). Prefer delegating to IOM.
2. **`InvestmentModelStore` / store params** reimplement `AbstractModelStore` plumbing IOM already
   generalizes; the only real investment-specific bit is op-vs-capacity time-step count per key.
   _(status: partly done — store params consolidated onto `IOM.ModelStoreParams`; the store type
   itself is still PSIN-local.)_
3. **`OptimizationContainer(settings, jump_model)` constructor** rebuilt IOM's struct field-by-field.
   _(status: DONE — now delegates to IOM's constructor, passing the `Portfolio` as the duck-typed
   "system".)_

### Tier D — Reuse IOM abstractions PSIN reinvents (verify overlap)
1. (DONE) **Variable / expression base types:** IOM already exports `InvestmentVariableType`,
   `OperationsVariableType`, `FeasibilityVariableType`, `BuildInvestmentVariableType`,
   `InvestmentExpressionType`, `OperationsExpressionType`, `FeasibilityExpressionType`,
   `CumulativeInvestmentExpressionType`. PSIN's `src/base/{variables,expressions,abstract_formulation_types}.jl`
   should **subtype / reuse these** rather than define parallel axes. Cleanest early win; feeds IOM's
   `src/investments/` stub.
2. **Operations cost-curve code:** PSIN's `.../objective_function/linear_curve.jl` operates on the
   same `IS.CostCurve`/`LinearCurve` types as IOM's `add_variable_cost_to_objective!`. The
   **operations** (variable O&M / fuel) portion likely duplicates IOM's pipeline — verify and
   delegate. (Capital / DCF cost code stays.)

### Tier E — Port UP to IOM (generic infra IOM lacks — the "move to IOM" list)
1. (DONE) **`TimeMapping` / `InvestmentIntervals` / `OperationalPeriods`** (`src/base/time_mapping.jl`) —
   a generic multi-stage (investment horizon → representative operational periods) index abstraction
   over plain `Dates`. IOM only has flat `time_steps`. **Highest-value port-up**; belongs in IOM
   (or `IOM/src/investments/`).
2. **The investment formulation model type** (`TechnologyModel{D,A,B,C}`, `RequirementModel{D,B}`) —
   generalizes IOM's `DeviceModel{D,B}`/`ServiceModel{D,B}` to 3 axes. Likely destination is IOM's
   stubbed `src/investments/`; port the generic multi-axis model-container pattern up, leaving
   PSIP-typed instances in PSIN.
3. **`InvestmentContainerData`-in-`Settings.ext` pattern** — formalize as a documented IOM extension
   point (typed data on `Settings.ext` + container getters) instead of ad-hoc `Dict{String,Any}`.
4. **`SimulationInfo`** — trivial bookkeeping (number / sequence_uuid / run_status) that IOM/ISOPT
   could own generically.

### Tier F — Keep in PSIN (domain-specific, no change)
`capital/` (DCF), `operation/` cost models, `network_models/` (capacity-expansion balance),
`requirement_models/` (ESR / policy), all `technology_models/technologies/*_tech.jl` + constructors,
and `base/{variables,constraints,expressions,technology_model,requirement_model,time_mapping,
transport_model,investment_model_template,investment_container_data,abstract_formulation_types}.jl`
(once they subtype IOM's base types per Tier D).

---

## Suggested sequencing
1. **Tier A + remaining B** — pure deletions / import-swaps; low risk; keep the test suite green after
   each batch.
2. **Tier D.1** — subtype IOM's exported investment variable/expression types (unlocks
   `src/investments/` integration).
3. **Tier E.1** (port `TimeMapping` up) + **D.2** (formulation model container) — the substantive IOM
   enrichment.
4. **Tier C** last — PSIN's copies drifted from IOM's hardened versions.

---

## Integration model established during the psy6 → IOM work (for reference)
- **IOM must not depend on PSIP.** Integration is duck-typed: PSIN passes the real `PSIP.Portfolio`
  as the "system" and implements the accessors IOM calls generically
  (`IOM.get_base_power(::PSIP.Portfolio) = 1.0`, `IS.stores_time_series_in_memory(::PSIP.Portfolio)`).
- **IOM changes are additive-only.** The only IOM additions required were the system-less defaults
  `get_base_power(::Nothing) = 1.0`, `stores_time_series_in_memory(::Nothing) = false`, and
  `Settings(; kwargs...)` (for building a bare container without a domain system, e.g. unit tests).
- PSIN's container **delegates to** `IOM.OptimizationContainer(sys, settings, jump_model, T)`; store
  params use `IOM.ModelStoreParams`; `list_*_keys` use IOM's type-based `list_keys` (`VariableType`,
  `ConstraintType`, `AuxVariableType`, `ExpressionType`).
