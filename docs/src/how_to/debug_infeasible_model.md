# [Debug an Infeasible Model](@id debug_how_to)

This guide shows how to find out why [`build!`](@ref) or [`solve!`](@ref) returned
`FAILED`.

```julia
using PowerSystemsInvestments
using HiGHS
using Logging
const PSINV = PowerSystemsInvestments
```

## Step 1: Check the returned status

[`build!`](@ref) and [`solve!`](@ref) do not throw an error when they fail. Check the
status they return:

```julia
build_status = build!(model; output_dir="results")
run_status = solve!(model)
```

A successful build returns `BUILT` and a successful solve returns
`SUCCESSFULLY_FINALIZED`.

## Step 2: Read the log file

The error and its stack trace are written to `investment_problem.log` in the output
directory:

```julia
print(read(joinpath("results", "investment_problem.log"), String))
```

Errors are also printed to the console. To see warnings and informational messages there
as well, lower the `console_level`:

```julia
build!(model; output_dir="results", console_level=Logging.Info)
```

## Step 3: If the build failed, check the template and the time series

Common causes of a failed build are reported in the log as follows:

| Message in the log                                                                        | Cause                                                                                                                                 |
|:----------------------------------------------------------------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------- |
| `Technology with name ... was added in a Formulation but does not exist in the Portfolio` | A name in the template is misspelled, or the technology type in the template does not match the technology                            |
| `Multiple technology models defined for the same technology`                              | A name appears in more than one call to [`set_technology_model!`](@ref)                                                               |
| A `MethodError` for `construct_technologies!` or `add_constraints!`                       | The combination of technology type and formulation is not implemented; see the [Formulation Library](@ref formulation_library_intro)  |
| An error retrieving a time series                                                         | A time series is missing, misnamed, or tagged with the wrong `"year"` or `"rep_day"`; see [Time Series Names](@ref time_series_names) |
| `Initial timestamp of timeseries ... does not match`                                      | A time series does not start at the first time stamp of its representative period                                                     |
| `target_year=... is not within any investment period`                                     | The target year of a requirement is outside the investment periods                                                                    |

## Step 4: If the solve failed, check that demand can be met

Demand must be met exactly in every time step; there is no unserved energy. A model is
infeasible if the technologies in the template cannot supply the demand in some time step,
even when built to their maximum capacity. Check that:

  - Every demand has enough candidate capacity in its region, or enough transport capacity
    to its region, to cover its peak
  - The maximum capacities in `capacity_limits` are not too low
  - Variable technologies are not the only supply in time steps where their capacity
    factor is zero
  - An energy share requirement can be met by its contributing technologies

## Step 5: Compute the conflicting constraints

If the cause is not apparent, ask the solver for an irreducible infeasible set: a small
set of constraints that cannot all be satisfied together. Create the model with
`calculate_conflict` and with variable names stored:

```julia
model = InvestmentModel(
    template,
    SingleInstanceSolve,
    portfolio;
    optimizer=HiGHS.Optimizer,
    calculate_conflict=true,
    store_variable_names=true,
)
build!(model; output_dir="results")
solve!(model)
```

The constraints in the conflict are written to the log. To get them as a dictionary from
the constraint key to the indices of the conflicting constraints:

```julia
container = PSINV.get_optimization_container(model)
conflict = get_infeasibility_conflict(container)
```

!!! note
    
    The solver must support conflict refinement. If it does not, the log reports that the
    conflict cannot be computed.

## Step 6: Inspect the optimization problem

When a solve fails, the `JuMP` model is written to `infeasible_CEM.json` in the output
directory, in [MathOptFormat](https://jump.dev/MathOptFormat/). Read it with `JuMP` to
examine it or to solve it with a different solver:

```julia
using JuMP
jump_model = read_from_file(joinpath("results", "infeasible_CEM.json"))
```

The `JuMP` model is also available directly from the model:

```julia
jump_model = PSINV.get_jump_model(model)
```

### See also

  - [Configure the Solver and Logging](@ref solver_logging_how_to)
  - [How a Model is Built](@ref build_process)
