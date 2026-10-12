# [How a Model is Built](@id build_process)

Calling [`build!`](@ref) on an [`InvestmentModel`](@ref) turns a template and a `Portfolio`
into a `JuMP` optimization problem. This page explains how that happens, which is useful
background for reading the log file, interpreting result keys, and adding new formulations.

## The optimization container

The optimization problem is held in an *optimization container*, which wraps the
`JuMP.Model` and keeps track of everything added to it. Variables, constraints, and
expressions are stored in dictionaries, and each entry holds an array indexed by technology
name and time.

Entries are identified by a *key* made of three parts:

  - The type of the variable, constraint, or expression, for example
    [`BuildCapacity`](@ref)
  - The type of technology it belongs to, for example `SupplyTechnology{ThermalStandard}`
  - The name of the formulation that created it, for example `"ContinuousInvestment"`

The third part is needed because technologies of the same type can use different
formulations. If some thermal technologies use [`ContinuousInvestment`](@ref) and others
use [`IntegerInvestment`](@ref), their build variables are stored under two keys.

The same keys are used to read the results after the model is solved, which is why reading
a result requires all three parts.

Entries that describe the whole problem instead of a type of technology, such as the
[`EnergyBalance`](@ref) expression, use `Portfolio` as their second part and have no
formulation name.

## Grouping technologies

A template assigns formulations to technologies by name. Before anything is added to the
problem, the build regroups those assignments by formulation: all of the technologies of
one type that share an investment formulation are collected together, and likewise for
operations and feasibility formulations.

Each group is handled by one call to a constructor function that is selected, through
multiple dispatch, by the technology type and the formulation. This is why a formulation is
written once for a technology type and applies to every technology of that type that uses
it.

Technologies whose `available` field is `false` are dropped from their groups, and the
build fails if a name in the template does not exist in the `Portfolio` or appears in more
than one technology model.

## Two stages

The problem is built in two passes over the groups, because some parts of the problem
depend on others that may not exist yet.

```
initialize     time mapping, financial data, empty energy balance expressions

argument       for each group:        create variables
stage                                 create expressions, such as installed capacity
                                      add contributions to the energy balance
               for each requirement:  create expressions from technology expressions

               transport model:       constrain the energy balance of each region

model          for each group:        add cost terms to the objective function
stage                                 add constraints
               for each requirement:  add constraints
```

In the **argument stage**, each group creates its variables and the expressions that other
parts of the problem will need. The most important shared expression is the
[`EnergyBalance`](@ref): it starts empty for each region and time step, and every supply,
demand, storage, and transport formulation adds its contribution to it.

Once every group has contributed, the transport model adds the balance constraints. It
does not need to know which technologies exist; it only constrains the finished expression.
This is what allows new technology types to be added without modifying the transport
formulations.

In the **model stage**, each group adds its cost terms and its constraints. By this point,
every expression exists, so a constraint can refer to expressions created by a different
formulation. An operations constraint that limits dispatch by installed capacity uses the
capacity expression created by the investment formulation of the same technology, whichever
one that is.

Requirements follow the technologies within each stage, for the same reason: an energy
share requirement is built from the energy expressions that the technology formulations
create.

## Status and logging

[`build!`](@ref) and [`solve!`](@ref) do not throw an error when something goes wrong
inside them. They catch the error, write it to the log file `investment_problem.log` in
the output directory, and return a status. A build returns `BUILT` or `FAILED`; a solve
returns `SUCCESSFULLY_FINALIZED` or `FAILED`.

This behavior comes from the infrastructure shared with the Sienna operations packages,
where a model is often one step of a long simulation that should record a failure and stop
cleanly. For an investment model, the practical consequence is that the returned status
must be checked, and the log file is the place to look for the cause of a failure.

## After the solve

When the solve succeeds, the values of all variables and of the expressions marked for
output are copied from the `JuMP.Model` into a result store that is kept in memory with
the model. Reading a result afterward reads from that store, not from the solver. The
problem and the results are also serialized to the output directory.
