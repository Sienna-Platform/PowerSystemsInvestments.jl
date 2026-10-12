# [Supply Technology Formulations](@id supply_formulations)

Formulations for `SupplyTechnology{T}`, where `T` is a `PowerSystems.jl` generator type.
See the [Formulation Library](@ref formulation_library_intro) introduction for the
nomenclature and the valid combinations.

### Table of Contents

 1. [Investment formulations](@ref supply_investment)
    
      + [`ContinuousInvestment`](@ref supply_continuous)
      + [`IntegerInvestment`](@ref supply_integer)
      + [`BinaryInvestment`](@ref supply_binary)

 2. [Operations formulations](@ref supply_operations)
    
      + [`BasicDispatch`](@ref supply_basic_dispatch)
      + [`BasicDispatchWithBudget`](@ref supply_budget_dispatch)
 3. [Feasibility formulations](@ref supply_feasibility)

* * *

## [Investment formulations](@id supply_investment)

All investment formulations share the same static parameters, expression names, objective
terms, and capacity constraint. They differ in the build variable and in how it adds to
the installed capacity.

**Static Parameters:**

  - ``K^0_g`` = `PowerSystemsInvestmentsPortfolios.get_existing_capacity_mw(portfolio, technology)`
  - ``K^\min_g`` = `PowerSystemsInvestmentsPortfolios.get_capacity_limits(technology).min`
  - ``K^\max_g`` = `PowerSystemsInvestmentsPortfolios.get_capacity_limits(technology).max`
  - ``U_g`` = `PowerSystemsInvestmentsPortfolios.get_unit_size(technology)`

**Objective:**

Adds a capital cost term and a fixed cost term for [`BuildCapacity`](@ref). See
[Objective Function](@ref objective_function). `SupplyTechnology{RenewableDispatch}` has no
fixed cost term.

**Constraints:**

`MaximumCumulativeCapacity` limits the installed capacity in every investment period:

```math
k_{g,i} \le K^\max_g, \quad \forall i \in \mathcal{I}
```

### [`ContinuousInvestment`](@id supply_continuous)

See [`ContinuousInvestment`](@ref).

**Variables:**

  - [`BuildCapacity`](@ref):
    
      + Bounds: [``K^\min_g``, ``K^\max_g``]
      + Symbol: ``b_{g,i}``, in MW

**Expressions:**

[`CumulativeCapacity`](@ref), the capacity installed up to and including investment period
``i``:

```math
k_{g,i} = K^0_g + \sum_{i' \le i} b_{g,i'}, \quad \forall i \in \mathcal{I}
```

### [`IntegerInvestment`](@id supply_integer)

See [`IntegerInvestment`](@ref).

**Variables:**

  - [`BuildCapacity`](@ref):
    
      + Integer
      + Bounds: [``K^\min_g``, ``K^\max_g``]
      + Symbol: ``b_{g,i}``, the number of units built

!!! warning
    
    The bounds of the integer variable are the capacity limits of the technology, which are
    in MW, applied to a number of units. The installed capacity is still limited to
    ``K^\max_g`` by the `MaximumCumulativeCapacity` constraint.

**Expressions:**

[`CumulativeCapacity`](@ref):

```math
k_{g,i} = K^0_g + \sum_{i' \le i} U_g \, b_{g,i'}, \quad \forall i \in \mathcal{I}
```

### [`BinaryInvestment`](@id supply_binary)

See [`BinaryInvestment`](@ref).

**Variables:**

  - [`BuildCapacity`](@ref):
    
      + Bounds: [0.0, ``K^\max_g``]
      + Symbol: ``b_{g,i}``

  - A binary variable ``u_{g,i}`` for each investment period. It is added to the `JuMP`
    model but is not stored in the optimization container or in the results.

**Constraints:**

The build variable is either zero or the maximum capacity:

```math
b_{g,i} = K^\max_g \, u_{g,i}, \quad \forall i \in \mathcal{I}
```

**Expressions:**

[`CumulativeCapacity`](@ref) is formed as for [`IntegerInvestment`](@ref supply_integer):

```math
k_{g,i} = K^0_g + \sum_{i' \le i} U_g \, b_{g,i'}, \quad \forall i \in \mathcal{I}
```

!!! warning
    
    Because the build variable is multiplied by the unit size ``U_g``, the capacity added
    by a build decision is ``U_g \, K^\max_g``. It equals the maximum capacity only when
    the unit size is 1.0.

* * *

## [Operations formulations](@id supply_operations)

### [`BasicDispatch`](@id supply_basic_dispatch)

See [`BasicDispatch`](@ref).

**Variables:**

  - [`ActivePowerVariable`](@ref):
    
      + Bounds: [0.0, ]
      + Symbol: ``p_{g,t}``, in MW

**Time Series Parameters:**

For `SupplyTechnology{RenewableDispatch}` and `SupplyTechnology{HydroDispatch}`:

  - ``F_{g,t}``: capacity factor, from the time series `"ops_variable_cap_factor"`

`SupplyTechnology{ThermalStandard}` has no time series parameters.

**Expressions:**

Adds ``p_{g,t}`` to the [`EnergyBalance`](@ref) expression of the region of the technology.

Creates [`WeightedEnergyGeneration`](@ref) for each operational period:

```math
W_k \sum_{t \in \mathcal{T}_k} p_{g,t}, \quad \forall k \in \mathcal{K}
```

**Objective:**

Adds a variable cost term for [`ActivePowerVariable`](@ref). See
[Objective Function](@ref objective_function).

**Constraints:**

`ActivePowerLimitsConstraint` limits the dispatch to the capacity installed in the
investment period that the time step belongs to. For `SupplyTechnology{ThermalStandard}`:

```math
p_{g,t} \le k_{g,i(t)}, \quad \forall t \in \mathcal{T}
```

For `SupplyTechnology{RenewableDispatch}` and `SupplyTechnology{HydroDispatch}`:

```math
p_{g,t} \le F_{g,t} \, k_{g,i(t)}, \quad \forall t \in \mathcal{T}
```

### [`BasicDispatchWithBudget`](@id supply_budget_dispatch)

See [`BasicDispatchWithBudget`](@ref). Implemented for `SupplyTechnology{HydroDispatch}`.

**Variables:**

  - [`ActivePowerVariable`](@ref):
    
      + Bounds: [0.0, ]
      + Symbol: ``p_{g,t}``, in MW

**Time Series Parameters:**

  - ``B_{g,t}``: energy budget, as a fraction of the installed capacity, from the time
    series `"ops_hydro_budget"`

**Expressions:**

The same as [`BasicDispatch`](@ref supply_basic_dispatch).

**Objective:**

The same as [`BasicDispatch`](@ref supply_basic_dispatch).

**Constraints:**

`ActivePowerLimitsConstraint`:

```math
p_{g,t} \le k_{g,i(t)}, \quad \forall t \in \mathcal{T}
```

[`HydroEnergyBudgetConstraint`](@ref) limits the energy dispatched over each operational
period. The budget of a period is the sum of the budget time series over the period:

```math
\sum_{t \in \mathcal{T}_k} p_{g,t} \le k_{g,i(k)} \sum_{t \in \mathcal{T}_k} B_{g,t}, \quad \forall k \in \mathcal{K}
```

A budget time series with the constant value 0.5 over a 24-hour period limits the energy
to 12 hours of production at full capacity.

* * *

## [Feasibility formulations](@id supply_feasibility)

### `BasicDispatchFeasibility`

See [`BasicDispatchFeasibility`](@ref). Adds the installed capacity of the technology to
the `FeasibilitySurplus` expression of its region, for each time step of the feasibility
periods. Used only when the template has feasibility periods; see
[Implementation Status](@ref implementation_status).
