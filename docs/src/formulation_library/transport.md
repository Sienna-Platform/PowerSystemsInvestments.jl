# [Transport Technology Formulations](@id transport_formulations)

Formulations for the technologies that move energy between regions:
`AggregateTransportTechnology{T}`, which connects two zones, and
`NodalACTransportTechnology{T}`, which connects two nodes. See the
[Formulation Library](@ref formulation_library_intro) introduction for the nomenclature and
the valid combinations.

Each transport technology takes part in the energy balance of only one transport
formulation:

| Technology type                | Transport formulation             | Losses |
|:------------------------------ |:--------------------------------- |:------ |
| `AggregateTransportTechnology` | [`MultiRegionBalanceModel`](@ref) | Yes    |
| `NodalACTransportTechnology`   | [`NodalBalanceModel`](@ref)       | No     |

With a [`SingleRegionBalanceModel`](@ref), transport technologies add nothing to the energy
balance.

* * *

## Investment formulations

### `ContinuousInvestment`

See [`ContinuousInvestment`](@ref).

**Variables:**

  - [`BuildCapacity`](@ref):
    
      + Bounds: [0.0, ``K^\max_g``]
      + Symbol: ``b_{g,i}``, in MW

**Static Parameters:**

  - ``K^0_g`` = `PowerSystemsInvestmentsPortfolios.get_existing_capacity_mw(portfolio, technology)`
  - ``K^\max_g`` = `PowerSystemsInvestmentsPortfolios.get_capacity_limits(technology).max`

**Expressions:**

[`CumulativeCapacity`](@ref), the capacity installed up to and including investment period
``i``:

```math
k_{g,i} = K^0_g + \sum_{i' \le i} b_{g,i'}, \quad \forall i \in \mathcal{I}
```

**Objective:**

Adds a capital cost term for [`BuildCapacity`](@ref). There is no fixed cost term. See
[Objective Function](@ref objective_function).

**Constraints:**

`MaximumCumulativeCapacity`:

```math
k_{g,i} \le K^\max_g, \quad \forall i \in \mathcal{I}
```

* * *

## Operations formulations

### `BasicDispatch`

See [`BasicDispatch`](@ref).

**Variables:**

  - [`FlowActivePowerVariable`](@ref):
    
      + Bounds: unbounded for `AggregateTransportTechnology`;
        [``-K^\max_g``, ``K^\max_g``] for `NodalACTransportTechnology`
      + Symbol: ``f_{g,t}``, in MW. Positive from the start region to the end region.

**Static Parameters:**

For `AggregateTransportTechnology`:

  - ``L_g`` = `PowerSystemsInvestmentsPortfolios.get_line_loss(technology)`, the fraction
    of the flow that is lost

**Expressions:**

For `AggregateTransportTechnology` with a [`MultiRegionBalanceModel`](@ref), adds to the
[`EnergyBalance`](@ref) expression of the two zones it connects:

```math
\begin{align*}
& -f_{g,t} \quad \text{in the start region} \\
& (1 - L_g) \, f_{g,t} \quad \text{in the end region}
\end{align*}
```

For `NodalACTransportTechnology` with a [`NodalBalanceModel`](@ref), adds ``-f_{g,t}`` at
the start node and ``f_{g,t}`` at the end node.

!!! note
    
    Losses are applied in the end region for flows in both directions. When the flow is
    negative, from the end region to the start region, the end region supplies
    ``(1 - L_g) \, |f_{g,t}|`` and the start region receives ``|f_{g,t}|``.

**Constraints:**

The flow in either direction is limited by the installed capacity:

```math
-k_{g,i(t)} \le f_{g,t} \le k_{g,i(t)}, \quad \forall t \in \mathcal{T}
```

The two sides are stored as separate constraints:

| Technology type                | Upper bound                                                       | Lower bound                                                          |
|:------------------------------ |:----------------------------------------------------------------- |:-------------------------------------------------------------------- |
| `AggregateTransportTechnology` | `ActivePowerLimitsConstraint`, formulation name `"BasicDispatch"` | `ActivePowerLimitsConstraint`, formulation name `"BasicDispatch_lb"` |
| `NodalACTransportTechnology`   | `FlowActivePowerUpperBoundConstraint`                             | `ActivePowerLimitsConstraint`                                        |

* * *

## Feasibility formulations

See [`BasicDispatchFeasibility`](@ref). Transport technologies add nothing to the model in
the feasibility periods.
