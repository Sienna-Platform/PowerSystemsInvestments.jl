# [Energy Balance Formulations](@id energy_balance_formulations)

Formulations selected by the [`TransportModel`](@ref) of the template. They determine the
regions in which supply and demand must balance. See the
[Formulation Library](@ref formulation_library_intro) introduction for the nomenclature.

## The `EnergyBalance` expression

All three formulations constrain the same [`EnergyBalance`](@ref) expression,
``n_{r,t}``, which is created for every region ``r`` and operational time step ``t``. Each
technology formulation adds its contribution to the expression of its region:

```math
n_{r,t} = \sum_{g \in \mathcal{G}^\text{supply}_r} p_{g,t} + \sum_{g \in \mathcal{G}^\text{storage}_r} \left( p^\text{out}_{g,t} - p^\text{in}_{g,t} \right) - \sum_{g \in \mathcal{G}^\text{demand}_r} D_{g,t} + \sum_{g \in \mathcal{G}^\text{to}_r} (1 - L_g) \, f_{g,t} - \sum_{g \in \mathcal{G}^\text{from}_r} f_{g,t}
```

where ``\mathcal{G}^\text{storage}_r`` includes co-located technologies,
``\mathcal{G}^\text{to}_r`` are the transport technologies that end in region ``r``, and
``\mathcal{G}^\text{from}_r`` are those that start in it.

The formulations differ in the set of regions ``\mathcal{R}``.

* * *

## `SingleRegionBalanceModel`

See [`SingleRegionBalanceModel`](@ref).

There is one region, named `"SingleRegion"`, to which every technology contributes
regardless of the region it is assigned to in the `Portfolio`. Transport technologies do
not contribute.

**Constraints:**

`SingleRegionBalanceConstraint`:

```math
n_t = 0, \quad \forall t \in \mathcal{T}
```

* * *

## `MultiRegionBalanceModel`

See [`MultiRegionBalanceModel`](@ref).

The regions are the `Zone`s of the `Portfolio`. Each supply, storage, and demand technology
contributes to the zone it is assigned to and must be assigned to exactly one.
`AggregateTransportTechnology` technologies contribute to the two zones they connect.

**Constraints:**

`MultiRegionBalanceConstraint`:

```math
n_{r,t} = 0, \quad \forall r \in \mathcal{R}, \ \forall t \in \mathcal{T}
```

* * *

## `NodalBalanceModel`

See [`NodalBalanceModel`](@ref).

The regions are the `Node`s of the `Portfolio`. `NodalACTransportTechnology` technologies
contribute to the two nodes they connect, without losses. Flows are limited only by
capacity; no power flow equations are included.

**Constraints:**

[`NodalBalanceConstraint`](@ref):

```math
n_{r,t} = 0, \quad \forall r \in \mathcal{R}, \ \forall t \in \mathcal{T}
```

* * *

## Reading the balance constraints

Balance constraints belong to the whole problem, not to a type of technology, so their key
uses `Portfolio` in place of a technology type and has no formulation name. See
[How a Model is Built](@ref build_process).

!!! note
    
    The `use_slacks` option of [`TransportModel`](@ref) is not used. The balance
    constraints are always equalities with no slack variables.
