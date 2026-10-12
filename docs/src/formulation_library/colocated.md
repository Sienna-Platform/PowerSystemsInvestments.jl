# [Co-located Technology Formulations](@id colocated_formulations)

Formulations for `ColocatedSupplyStorageTechnology{T}`: a wind plant, a solar plant, and a
storage device that share an inverter and a single connection to the grid. See the
[Formulation Library](@ref formulation_library_intro) introduction for the nomenclature and
the valid combinations.

The five components are sized independently. Their operation is linked by an internal
balance, and the exchange with the grid is limited by the inverter.

* * *

## Investment formulations

See [`ContinuousInvestment`](@ref).

**Variables:**

Each has bounds [0.0, ] and one value per investment period.

| Variable                        | Symbol                   | Unit |
|:------------------------------- |:------------------------ |:---- |
| [`BuildWindCapacity`](@ref)     | ``b^\text{wind}_{g,i}``  | MW   |
| [`BuildSolarCapacity`](@ref)    | ``b^\text{solar}_{g,i}`` | MW   |
| [`BuildPowerCapacity`](@ref)    | ``b^\text{pw}_{g,i}``    | MW   |
| [`BuildEnergyCapacity`](@ref)   | ``b^\text{en}_{g,i}``    | MWh  |
| [`BuildInverterCapacity`](@ref) | ``b^\text{inv}_{g,i}``   | MW   |

**Expressions:**

For each component ``c`` of wind, solar, power, energy, and inverter, a cumulative capacity
expression: [`CumulativeWindCapacity`](@ref), [`CumulativeSolarCapacity`](@ref),
[`CumulativePowerCapacity`](@ref), [`CumulativeEnergyCapacity`](@ref), and
[`CumulativeInverterCapacity`](@ref).

```math
k^c_{g,i} = K^0_g + \sum_{i' \le i} b^c_{g,i'}, \quad \forall i \in \mathcal{I}
```

``K^0_g`` = `PowerSystemsInvestmentsPortfolios.get_existing_capacity_mw(portfolio, technology)`
for every component.

**Objective:**

Adds a capital cost term and a fixed cost term for each of the five build variables, using
the capital cost and operation cost of the matching component: `capital_costs_wind`,
`capital_costs_solar`, `capital_costs_power`, `capital_costs_energy`, and
`capital_costs_inverter`. See [Objective Function](@ref objective_function).

**Constraints:**

`MaximumCumulativePowerCapacity` and `MaximumCumulativeEnergyCapacity` limit the installed
storage capacities in every investment period:

```math
\begin{align*}
& k^\text{pw}_{g,i} \le K^{\max,\text{pw}}_g, \quad \forall i \in \mathcal{I} \\
& k^\text{en}_{g,i} \le K^{\max,\text{en}}_g, \quad \forall i \in \mathcal{I}
\end{align*}
```

!!! warning
    
    The maximum wind, solar, and inverter capacities of the technology are not enforced.
    The constraints named `MaximumCumulativeWindCapacity`,
    `MaximumCumulativeSolarCapacity`, and `MaximumCumulativeInverterCapacity` repeat the
    limits on the storage power and energy capacities.

* * *

## Operations formulations

[`ChronologicalColocatedDispatch`](@ref) and [`CyclicalColocatedDispatch`](@ref) share
everything except the treatment of the stored energy at the first time step of each
operational period.

**Variables:**

Each has bounds [0.0, ] and one value per operational time step.

| Variable                               | Symbol                   | Description                         |
|:-------------------------------------- |:------------------------ |:----------------------------------- |
| [`ActiveOutPowerVariable`](@ref)       | ``p^\text{out}_{g,t}``   | Power injected into the grid, in MW |
| [`ActiveInPowerVariable`](@ref)        | ``p^\text{in}_{g,t}``    | Power drawn from the grid, in MW    |
| [`ActivePowerWindVariable`](@ref)      | ``p^\text{wind}_{g,t}``  | Wind production, in MW              |
| [`ActivePowerSolarVariable`](@ref)     | ``p^\text{solar}_{g,t}`` | Solar production, in MW             |
| [`ActivePowerChargeVariable`](@ref)    | ``p^\text{ch}_{g,t}``    | Storage charging, in MW             |
| [`ActivePowerDischargeVariable`](@ref) | ``p^\text{ds}_{g,t}``    | Storage discharging, in MW          |
| [`StateOfChargeVariable`](@ref)        | ``e_{g,t}``              | Energy stored, in MWh               |

**Static Parameters:**

  - ``\eta^\text{in}_g`` = `PowerSystemsInvestmentsPortfolios.get_efficiency_storage(technology).in`
  - ``\eta^\text{out}_g`` = `PowerSystemsInvestmentsPortfolios.get_efficiency_storage(technology).out`
  - ``\Delta_k``: length of the time steps of operational period ``k`` in hours

**Time Series Parameters:**

  - ``F^\text{wind}_{g,t}``: wind capacity factor, from the time series
    `"ops_wind_variable_cap_factor"`
  - ``F^\text{solar}_{g,t}``: solar capacity factor, from the time series
    `"ops_solar_variable_cap_factor"`

**Expressions:**

Adds ``p^\text{out}_{g,t} - p^\text{in}_{g,t}`` to the [`EnergyBalance`](@ref) expression
of the region of the technology.

Creates [`WeightedEnergyGeneration`](@ref) for each operational period, as the net
injection into the grid:

```math
W_k \sum_{t \in \mathcal{T}_k} \left( p^\text{out}_{g,t} - p^\text{in}_{g,t} \right), \quad \forall k \in \mathcal{K}
```

**Objective:**

Adds a variable cost term for the wind, solar, charge, and discharge variables, using the
operation cost of the matching component. See [Objective Function](@ref objective_function).

**Constraints:**

`ColocatedInternalBalanceConstraint` links the exchange with the grid to the components:

```math
\begin{align*}
& p^\text{out}_{g,t} = p^\text{ds}_{g,t} + p^\text{wind}_{g,t} + p^\text{solar}_{g,t}, \quad \forall t \in \mathcal{T} \\
& p^\text{in}_{g,t} = p^\text{ch}_{g,t}, \quad \forall t \in \mathcal{T}
\end{align*}
```

`InputActivePowerVariableLimitsConstraint` and `OutputActivePowerVariableLimitsConstraint`
limit the exchange with the grid to the installed inverter capacity:

```math
\begin{align*}
& p^\text{in}_{g,t} \le k^\text{inv}_{g,i(t)}, \quad \forall t \in \mathcal{T} \\
& p^\text{out}_{g,t} \le k^\text{inv}_{g,i(t)}, \quad \forall t \in \mathcal{T}
\end{align*}
```

`ActivePowerWindVariableLimitsConstraint` and `ActivePowerSolarVariableLimitsConstraint`
limit production to the available resource:

```math
\begin{align*}
& p^\text{wind}_{g,t} \le F^\text{wind}_{g,t} \, k^\text{wind}_{g,i(t)}, \quad \forall t \in \mathcal{T} \\
& p^\text{solar}_{g,t} \le F^\text{solar}_{g,t} \, k^\text{solar}_{g,i(t)}, \quad \forall t \in \mathcal{T}
\end{align*}
```

`ActivePowerChargeVariableLimitsConstraint`,
`ActivePowerDischargeVariableLimitsConstraint`, and `StateOfChargeLimitsConstraint` limit
the storage to its installed capacities:

```math
\begin{align*}
& p^\text{ch}_{g,t} \le k^\text{pw}_{g,i(t)}, \quad \forall t \in \mathcal{T} \\
& p^\text{ds}_{g,t} \le k^\text{pw}_{g,i(t)}, \quad \forall t \in \mathcal{T} \\
& e_{g,t} \le k^\text{en}_{g,i(t)}, \quad \forall t \in \mathcal{T}
\end{align*}
```

`EnergyBalanceConstraint` links the stored energy between time steps:

```math
e_{g,t} = e_{g,t-1} + \Delta_k \left( \eta^\text{in}_g \, p^\text{ch}_{g,t} - \frac{p^\text{ds}_{g,t}}{\eta^\text{out}_g} \right)
```

The first time step of each operational period is treated as in the storage formulations:
[`ChronologicalColocatedDispatch`](@ref) follows
[`ChronologicalStorageDispatch`](@ref storage_chronological), and
[`CyclicalColocatedDispatch`](@ref) follows
[`CyclicalStorageDispatch`](@ref storage_cyclical).

* * *

## Feasibility formulations

See [`BasicDispatchFeasibility`](@ref). Used only when the template has feasibility
periods; see [Implementation Status](@ref implementation_status).
