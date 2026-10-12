# [Configure the Solver and Logging](@id solver_logging_how_to)

This guide shows how to choose a solver, set its options, and control what is printed and
logged when building and solving an [`InvestmentModel`](@ref).

```julia
using PowerSystemsInvestments
using HiGHS
using Logging
```

## Choose a solver

Pass the optimizer of any solver supported by
[`JuMP.jl`](https://jump.dev/JuMP.jl/stable/installation/#Supported-solvers) with the
`optimizer` keyword argument:

```julia
model = InvestmentModel(template, SingleInstanceSolve, portfolio; optimizer=HiGHS.Optimizer)
```

The solver must support linear programs, and mixed-integer programs if the template uses
[`IntegerInvestment`](@ref) or [`BinaryInvestment`](@ref).

## Set solver options

Use `optimizer_with_attributes`, which `PowerSystemsInvestments.jl` exports, to pass
options to the solver. The option names are those of the solver:

```julia
solver = optimizer_with_attributes(
    HiGHS.Optimizer,
    "mip_rel_gap" => 0.01,
    "time_limit" => 3600.0,
)
model = InvestmentModel(template, SingleInstanceSolve, portfolio; optimizer=solver)
```

## Show the solver log

The solver output is hidden by default. Show it with `optimizer_solve_log_print`:

```julia
model = InvestmentModel(
    template,
    SingleInstanceSolve,
    portfolio;
    optimizer=HiGHS.Optimizer,
    optimizer_solve_log_print=true,
)
```

## Show more messages in the console

[`build!`](@ref) and [`solve!`](@ref) print only errors to the console by default. Lower
the `console_level` to see warnings or informational messages:

```julia
build!(model; output_dir="results", console_level=Logging.Info)
solve!(model; console_level=Logging.Info)
```

## Change what is written to the log file

Messages are also written to the file `investment_problem.log` in the output directory, at
the `Info` level by default. Use `file_level` to change the level:

```julia
build!(model; output_dir="results", file_level=Logging.Debug)
```

The log file is overwritten by each [`build!`](@ref) and appended to by each
[`solve!`](@ref).

## Skip writing the problem to disk

By default, [`solve!`](@ref) serializes the problem to the output directory after solving
it, including a copy of the `JuMP` model and of the `Portfolio`. For large problems, this
can take a noticeable amount of time and disk space.

To skip the copy of the `Portfolio`, set `portfolio_to_file` when creating the model:

```julia
model = InvestmentModel(
    template,
    SingleInstanceSolve,
    portfolio;
    optimizer=HiGHS.Optimizer,
    portfolio_to_file=false,
)
```

To skip serializing the problem altogether, set `export_optimization_problem` when solving:

```julia
solve!(model; export_optimization_problem=false)
```

## Keep variable names for debugging

Variable and constraint names are not stored in the `JuMP` model by default, to save
memory. Keep them when you need to inspect the model:

```julia
model = InvestmentModel(
    template,
    SingleInstanceSolve,
    portfolio;
    optimizer=HiGHS.Optimizer,
    store_variable_names=true,
)
```

### See also

  - [Debug an Infeasible Model](@ref debug_how_to)
  - [`InvestmentModel`](@ref), for all of the keyword arguments
