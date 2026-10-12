# [Objective Function](@id objective_function)

The objective function minimizes the sum of capital terms and operation terms. This page
gives the expression for each term. For the reasoning behind them, see
[Cost Accounting](@ref cost_accounting).

```math
\min \quad \sum_{g} \sum_{i \in \mathcal{I}} \left( c^\text{cap}_{g,i} + c^\text{fom}_{g,i} \right) + \sum_{g} \sum_{t \in \mathcal{T}} c^\text{vom}_{g,t}
```

## Financial parameters

**Portfolio parameters:**

  - ``Y^0`` = `PowerSystemsInvestmentsPortfolios.get_base_year(portfolio)`
  - ``R`` = `PowerSystemsInvestmentsPortfolios.get_discount_rate(portfolio)`
  - ``\Pi`` = `PowerSystemsInvestmentsPortfolios.get_inflation_rate(portfolio)`

**Technology parameters**, from the `financial_data` of technology ``g``:

  - ``N_g`` = `PowerSystemsInvestmentsPortfolios.get_capital_recovery_period(financial_data)`
  - ``A_g`` = `PowerSystemsInvestmentsPortfolios.get_wacc(financial_data)`, the weighted
    average cost of capital
  - ``Y_g`` = `PowerSystemsInvestmentsPortfolios.get_technology_base_year(financial_data)`,
    the year the costs of the technology are expressed in

**Time parameters:**

  - ``Y_i``: year of the first date of investment period ``i``
  - ``Y_t``: year of time step ``t``
  - ``W_k``: weight of operational period ``k``

## Factors

The capital recovery factor converts an overnight cost into an equal yearly payment over
the capital recovery period:

```math
F^\text{crf}_g = \frac{A_g}{1 - (1 + A_g)^{-N_g}}
```

The present value factor converts that stream of yearly payments into a single value at
the time of the investment:

```math
F^\text{pv}_g = \frac{1 - (1 + R)^{-N_g}}{R}
```

The inflation factor converts the costs of a technology to base-year dollars:

```math
F^\text{inf}_g = (1 + \Pi)^{-(Y_g - Y^0)}
```

The discount factor converts a cost in year ``Y`` to its present value in the base year:

```math
F^\text{dis}(Y) = (1 + R)^{-(Y - Y^0)}
```

## Capital cost

For each build variable ``b_{g,i}`` with an overnight capital cost ``C^\text{cap}_g`` per
unit of capacity:

```math
c^\text{cap}_{g,i} = C^\text{cap}_g \, F^\text{crf}_g \, F^\text{pv}_g \, F^\text{inf}_g \, F^\text{dis}(Y_i) \, b_{g,i}
```

``C^\text{cap}_g`` is the proportional term of the capital cost curve of the technology.
Technologies with several build variables, such as storage, have one capital cost term for
each, with its own capital cost curve. These terms are also stored in the
[`CapitalCost`](@ref) expression.

## Fixed operation and maintenance cost

For each build variable ``b_{g,i}`` of a technology with a fixed cost
``C^\text{fom}_g``:

```math
c^\text{fom}_{g,i} = C^\text{fom}_g \, F^\text{crf}_g \, F^\text{pv}_g \, F^\text{inf}_g \, F^\text{dis}(Y_i) \, b_{g,i}
```

``C^\text{fom}_g`` is the `fixed` term of the operation cost of the technology. These terms
are also stored in the [`FixedOperationModelCost`](@ref) expression.

## Variable operation and maintenance cost

For each dispatch variable ``p_{g,t}`` with a variable cost ``C^\text{vom}_g``, in a time
step ``t`` of operational period ``k``:

```math
c^\text{vom}_{g,t} = W_k \, C^\text{vom}_g \, F^\text{inf}_g \, F^\text{dis}(Y_t) \, p_{g,t}
```

``C^\text{vom}_g`` is the proportional term of the variable cost curve of the technology.
Storage technologies have separate terms for charging and discharging. These terms are also
stored in the [`VariableOMCost`](@ref) expression.

!!! note
    
    Only the proportional term of each cost curve is used. Constant, quadratic, and
    piecewise-linear terms are ignored. Variable cost terms are not multiplied by the
    length of the time step, which assumes hourly time steps.

## Terms by technology

| Technology type                       | Capital cost | Fixed cost | Variable cost |
|:------------------------------------- |:------------ |:---------- |:------------- |
| `SupplyTechnology{RenewableDispatch}` | Yes          | No         | Yes           |
| Other `SupplyTechnology`              | Yes          | Yes        | Yes           |
| `StorageTechnology`                   | Yes          | Yes        | Yes           |
| `ColocatedSupplyStorageTechnology`    | Yes          | Yes        | Yes           |
| `AggregateTransportTechnology`        | Yes          | No         | No            |
| `NodalACTransportTechnology`          | Yes          | No         | No            |
| `DemandRequirement`                   | No           | No         | No            |
