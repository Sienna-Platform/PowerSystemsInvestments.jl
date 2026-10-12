# [Assign Formulations to Technologies](@id assign_formulations_how_to)

This guide shows how to choose the formulations used for the technologies in a `Portfolio`
by adding technology models to an [`InvestmentModelTemplate`](@ref).

It assumes you have a `Portfolio` named `portfolio` and a template named `template`. See
[Build and Solve a Capacity Expansion Model](@ref) for how to create them, and the
[Formulation Library](@ref formulation_library_intro) for the formulations that are valid
for each technology type.

```julia
using PowerSystemsInvestments
using PowerSystemsInvestmentsPortfolios
using PowerSystems
```

## Assign formulations to technologies by name

Call [`set_technology_model!`](@ref) with the names of the technologies, their type, and an
investment, an operations, and a feasibility formulation:

```julia
set_technology_model!(
    template,
    ["cheap_thermal", "expensive_thermal"],
    SupplyTechnology{ThermalStandard},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
```

The type must be the full type of the technologies, including its `PowerSystems.jl`
parameter. Every name must belong to a technology of that type in the `Portfolio`.

## Assign formulations to every technology of a type

Pass the `Portfolio` instead of a list of names to select all of the available technologies
of a type:

```julia
set_technology_model!(
    template,
    portfolio,
    SupplyTechnology{RenewableDispatch},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
```

The technologies are selected when the function is called. Technologies added to the
`Portfolio` afterward are not included.

## Use different formulations for technologies of the same type

Call [`set_technology_model!`](@ref) once for each group of names:

```julia
set_technology_model!(
    template,
    ["nuclear"],
    SupplyTechnology{ThermalStandard},
    IntegerInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
set_technology_model!(
    template,
    ["gas_cc", "gas_ct"],
    SupplyTechnology{ThermalStandard},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
```

A technology can appear in only one technology model. If a name is repeated, the build
fails.

## Reuse a technology model

Create a [`TechnologyModel`](@ref) and pass it in place of the type and formulations:

```julia
thermal_model = TechnologyModel(
    SupplyTechnology{ThermalStandard},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
set_technology_model!(template, ["cheap_thermal", "expensive_thermal"], thermal_model)
```

Use a technology model object for one group of names only. Passing the same object again
with different names replaces the names assigned to it earlier.

## Leave a technology out of the model

Technologies that are not assigned to a technology model are not included in the
optimization problem. To exclude a technology, leave its name out of every call to
[`set_technology_model!`](@ref).

Technologies whose `available` field is `false` are also excluded, even if they are named
in the template.

## Check the template

Display the template to see the technology models it contains:

```julia
template
```

!!! note
    
    The names assigned to each technology model are not checked until the model is built.
    If [`build!`](@ref) returns `FAILED`, look in the log file for a name that is not in
    the `Portfolio` or that is assigned twice. See
    [Debug an Infeasible Model](@ref debug_how_to).
