# [Formulations](@id formulation_axes)

A *formulation* is a set of variables, constraints, and cost terms that represents one
aspect of a technology. In `PowerSystemsInvestments.jl`, every technology is modeled with
three formulations at once. This page explains what the three are and why they are chosen
independently.

## Three questions about every technology

A capacity expansion model asks different questions of a technology at different time
scales:

 1. **Investment**: how much of it is built in each investment period, and what does that
    cost? This is answered once per investment period.
 2. **Operations**: given what has been built, how is it used in each hour of the periods
    that represent operation, and what does that cost?
 3. **Feasibility**: given what has been built, can the system still meet demand in a
    separate set of test periods?

Each question has its own abstract formulation type:
[`InvestmentTechnologyFormulation`](@ref), [`OperationsTechnologyFormulation`](@ref), and
[`FeasibilityTechnologyFormulation`](@ref). A [`TechnologyModel`](@ref) names one of each
for a type of technology:

```julia
TechnologyModel(
    SupplyTechnology{ThermalStandard},   # the type of technology
    ContinuousInvestment,                # how it is built
    BasicDispatch,                       # how it is operated
    BasicDispatchFeasibility,            # how it counts in the feasibility periods
)
```

## Why the three are independent

The answers to the three questions are mostly independent modeling decisions. Whether a
gas plant is built in whole units or in any amount has nothing to do with whether its
operation is modeled as simple dispatch or with more detail. Making each formulation a
separate choice means that:

  - Formulations combine. An investment formulation written once works with every
    operations formulation, so adding a new operations formulation does not require
    rewriting how capacity is built.
  - Detail can be added where it matters. Build decisions can be integer for the few
    technologies where unit size matters and continuous for the rest.
  - The effect of a simplification can be measured, by solving the same `Portfolio` with
    one formulation changed.

What links the three is installed capacity. The investment formulation creates the build
variables and an expression for the capacity installed in each investment period. The
operations and feasibility formulations use that expression as the limit on what the
technology can do in the hours that belong to that period.

## The technology type narrows the choice

Not every formulation makes sense for every technology. The type of the technology,
including its `PowerSystems.jl` parameter, determines which formulations are available and
what they do:

  - A storage technology needs an operations formulation that tracks stored energy, such
    as [`CyclicalStorageDispatch`](@ref)
  - [`BasicDispatch`](@ref) limits a `SupplyTechnology{RenewableDispatch}` with a capacity
    factor time series, and a `SupplyTechnology{ThermalStandard}` with its installed
    capacity alone
  - A demand technology is not a decision, so its investment formulation is
    [`StaticLoadInvestment`](@ref), which creates no variables

This is implemented with Julia's multiple dispatch: the equations for a technology are
methods selected by the technology type and the formulation type together. The
[Formulation Library](@ref formulation_library_intro) lists the valid combinations.

## One technology, one model

Formulations are assigned to technologies by name with [`set_technology_model!`](@ref).
Technologies of the same type do not have to share formulations: two
`SupplyTechnology{ThermalStandard}` technologies can be given different investment
formulations by assigning them in two separate calls. Each technology can belong to only
one technology model, and a technology that is not assigned to any model is left out of
the problem.

## Formulations that span technologies

Some parts of the problem do not belong to a single technology. They are specified once,
for the whole template:

  - The [`TransportModel`](@ref) decides where supply and demand must balance. Every
    technology formulation contributes to the balance of the region it is in, and the
    transport model turns those contributions into constraints.
  - A [`RequirementModel`](@ref) represents a policy that involves several technologies,
    such as an energy share requirement that compares the generation of some technologies
    with the demand of others. It is formulated after the technologies, from expressions
    that their formulations create.
  - The capital, operation, and feasibility models of the template define the time
    structure that all formulations share. See
    [Time Representation](@ref time_representation).
