# [Storage Technology Formulations](@id storage_formulations)

Formulations for `StorageTechnology{T}`, where `T` is a `PowerSystems.jl` storage type. See
the [Formulation Library](@ref formulation_library_intro) introduction for the nomenclature
and the valid combinations.

A storage technology has two capacities that are sized independently: a power capacity in
MW and an energy capacity in MWh.

### Table of Contents

 1. [Investment formulations](@ref storage_investment)

 2. [Operations formulations](@ref storage_operations)
    
      + [`ChronologicalStorageDispatch`](@ref storage_chronological)
      + [`CyclicalStorageDispatch`](@ref storage_cyclical)
 3. [Feasibility formulations](@ref storage_feasibility)

* * *

## [Investment formulations](@id storage_investment)

See [`ContinuousInvestment`](@ref) and [`IntegerInvestment`](@ref).

**Variables:**

  - [`BuildPowerCapacity`](@ref):
    
      + Bounds: [0.0, ]
      + Symbol: ``b^\text{pw}_{g,i}``, in MW

  - [`BuildEnergyCapacity`](@ref):
    
      + Bounds: [0.0, ]
      + Symbol: ``b^\text{en}_{g,i}``, in MWh

With [`IntegerInvestment`](@ref), both variables are integer and represent a number of
units.

**Static Parameters:**

  - ``K^{0,\text{pw}}_g`` = `PowerSystemsInvestmentsPortfolios.get_existing_capacity_mw(portfolio, technology)`
  - ``K^{0,\text{en}}_g`` = `PowerSystemsInvestmentsPortfolios.get_existing_capacity_mwh(portfolio, technology)`
  - ``K^{\max,\text{pw}}_g`` = `PowerSystemsInvestmentsPortfolios.get_capacity_limits_discharge(technology).max`
  - ``K^{\max,\text{en}}_g`` = `PowerSystemsInvestmentsPortfolios.get_capacity_limits_energy(technology).max`
  - ``U^\text{en}_g`` = `PowerSystemsInvestmentsPortfolios.get_unit_size_energy(technology)`

**Expressions:**

[`CumulativePowerCapacity`](@ref) and [`CumulativeEnergyCapacity`](@ref), the capacities
installed up to and including investment period ``i``. With
[`ContinuousInvestment`](@ref):

```math
\begin{align*}
& k^\text{pw}_{g,i} = K^{0,\text{pw}}_g + \sum_{i' \le i} b^\text{pw}_{g,i'}, \quad \forall i \in \mathcal{I} \\
& k^\text{en}_{g,i} = K^{0,\text{en}}_g + \sum_{i' \le i} b^\text{en}_{g,i'}, \quad \forall i \in \mathcal{I}
\end{align*}
```

With [`IntegerInvestment`](@ref):

```math
\begin{align*}
& k^\text{pw}_{g,i} = K^{0,\text{pw}}_g + \sum_{i' \le i} U^\text{en}_g \, b^\text{pw}_{g,i'}, \quad \forall i \in \mathcal{I} \\
& k^\text{en}_{g,i} = K^{0,\text{en}}_g + \sum_{i' \le i} U^\text{en}_g \, b^\text{en}_{g,i'}, \quad \forall i \in \mathcal{I}
\end{align*}
```

!!! warning
    
    With [`IntegerInvestment`](@ref), the energy unit size ``U^\text{en}_g`` is used for
    both the power and the energy capacity. The discharge unit size of the technology is
    not used.

**Objective:**

Adds a capital cost term for [`BuildPowerCapacity`](@ref), using the
`capital_costs_discharge` of the technology, and for [`BuildEnergyCapacity`](@ref), using
its `capital_costs_energy`. Adds a fixed cost term for each of the two variables, using the
`fixed` term of the operation cost of the technology in both. See
[Objective Function](@ref objective_function).

**Constraints:**

`MaximumCumulativePowerCapacity` and `MaximumCumulativeEnergyCapacity` limit the installed
capacities in every investment period:

```math
\begin{align*}
& k^\text{pw}_{g,i} \le K^{\max,\text{pw}}_g, \quad \forall i \in \mathcal{I} \\
& k^\text{en}_{g,i} \le K^{\max,\text{en}}_g, \quad \forall i \in \mathcal{I}
\end{align*}
```

* * *

## [Operations formulations](@id storage_operations)

The two operations formulations share everything except the constraint that links the
stored energy from one time step to the next.

**Variables:**

  - [`ActiveInPowerVariable`](@ref):
    
      + Bounds: [0.0, ]
      + Symbol: ``p^\text{in}_{g,t}``, in MW

  - [`ActiveOutPowerVariable`](@ref):
    
      + Bounds: [0.0, ]
      + Symbol: ``p^\text{out}_{g,t}``, in MW
  - [`StateOfChargeVariable`](@ref):
    
      + Bounds: [0.0, ]
      + Symbol: ``e_{g,t}``, in MWh

**Static Parameters:**

  - ``\eta^\text{in}_g`` = `PowerSystemsInvestmentsPortfolios.get_efficiency(technology).in`
  - ``\eta^\text{out}_g`` = `PowerSystemsInvestmentsPortfolios.get_efficiency(technology).out`
  - ``\Delta_k``: length of the time steps of operational period ``k`` in hours, taken from
    its first two time stamps

**Expressions:**

Adds ``p^\text{out}_{g,t} - p^\text{in}_{g,t}`` to the [`EnergyBalance`](@ref) expression
of the region of the technology.

Creates [`WeightedEnergyGeneration`](@ref) for each operational period, as the net
discharge:

```math
W_k \sum_{t \in \mathcal{T}_k} \left( p^\text{out}_{g,t} - p^\text{in}_{g,t} \right), \quad \forall k \in \mathcal{K}
```

**Objective:**

Adds a variable cost term for [`ActiveInPowerVariable`](@ref), using the
`charge_variable_cost` of the technology, and for [`ActiveOutPowerVariable`](@ref), using
its `discharge_variable_cost`. See [Objective Function](@ref objective_function).

**Constraints:**

`InputActivePowerVariableLimitsConstraint` and `OutputActivePowerVariableLimitsConstraint`
limit charging and discharging to the installed power capacity:

```math
\begin{align*}
& p^\text{in}_{g,t} \le k^\text{pw}_{g,i(t)}, \quad \forall t \in \mathcal{T} \\
& p^\text{out}_{g,t} \le k^\text{pw}_{g,i(t)}, \quad \forall t \in \mathcal{T}
\end{align*}
```

`StateOfChargeLimitsConstraint` limits the stored energy to the installed energy capacity:

```math
e_{g,t} \le k^\text{en}_{g,i(t)}, \quad \forall t \in \mathcal{T}
```

`EnergyBalanceConstraint` links the stored energy between time steps. Within an operational
period, for every time step except the first:

```math
e_{g,t} = e_{g,t-1} + \Delta_k \left( \eta^\text{in}_g \, p^\text{in}_{g,t} - \frac{p^\text{out}_{g,t}}{\eta^\text{out}_g} \right)
```

The first time step of each operational period depends on the formulation.

### [`ChronologicalStorageDispatch`](@id storage_chronological)

See [`ChronologicalStorageDispatch`](@ref).

The operational periods of an investment period are treated as a sequence. For the first
time step ``t`` of the first operational period of each investment period, the storage
starts empty:

```math
e_{g,t} = \Delta_k \left( \eta^\text{in}_g \, p^\text{in}_{g,t} - \frac{p^\text{out}_{g,t}}{\eta^\text{out}_g} \right)
```

For the first time step of every other operational period, the general equation applies,
so that the stored energy carries over from the last time step of the previous operational
period.

### [`CyclicalStorageDispatch`](@id storage_cyclical)

See [`CyclicalStorageDispatch`](@ref).

Each operational period is a closed cycle. For the first time step ``t`` of operational
period ``k``, with ``t^\text{end}_k`` the last time step of the same period:

```math
e_{g,t} = e_{g,t^\text{end}_k} + \Delta_k \left( \eta^\text{in}_g \, p^\text{in}_{g,t} - \frac{p^\text{out}_{g,t}}{\eta^\text{out}_g} \right)
```

* * *

## [Feasibility formulations](@id storage_feasibility)

### `BasicDispatchFeasibility`

See [`BasicDispatchFeasibility`](@ref). Used only when the template has feasibility
periods; see [Implementation Status](@ref implementation_status).
