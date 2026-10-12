# [Demand Formulations](@id demand_formulations)

Formulations for `DemandRequirement{T}`, where `T` is a `PowerSystems.jl` load type. See
the [Formulation Library](@ref formulation_library_intro) introduction for the nomenclature
and the valid combinations.

Demand is an input to the model. It creates no variables, constraints, or cost terms; it
only adds a fixed quantity to the energy balance of its region.

* * *

## Investment formulations

### `StaticLoadInvestment`

See [`StaticLoadInvestment`](@ref). Adds nothing to the model.

* * *

## Operations formulations

### `BasicDispatch`

See [`BasicDispatch`](@ref).

**Time Series Parameters:**

  - ``D_{g,t}``: demand in MW, from the time series `"ops_demand"`

**Expressions:**

Subtracts ``D_{g,t}`` from the [`EnergyBalance`](@ref) expression of the region of the
demand, for every operational time step.

Adds the weighted demand of each operational period to the [`WeightedEnergyDemand`](@ref)
expression of the region of the demand:

```math
W_k \sum_{t \in \mathcal{T}_k} D_{g,t}, \quad \forall k \in \mathcal{K}
```

!!! note
    
    Demand must be met in full in every time step. The `value_of_lost_load` of a
    `DemandRequirement` is not used, and there is no unserved energy variable.

* * *

## Feasibility formulations

### `BasicDispatchFeasibility`

See [`BasicDispatchFeasibility`](@ref). Subtracts the demand from the `FeasibilitySurplus`
expression of its region. Used only when the template has feasibility periods; see
[Implementation Status](@ref implementation_status).
