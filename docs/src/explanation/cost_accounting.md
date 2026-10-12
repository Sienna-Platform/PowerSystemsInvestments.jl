# [Cost Accounting](@id cost_accounting)

An investment model minimizes total cost, but the costs it adds up are of different kinds
and are incurred at different times. A power plant is paid for when it is built and then
costs money to run for decades. This page explains how `PowerSystemsInvestments.jl` puts
those costs on a common footing so that they can be compared. The exact expressions are in
the [Objective Function](@ref objective_function) reference.

## What is minimized

The objective function is the sum of two groups of terms:

  - **Capital terms**, which depend on the build variables: the capital cost of new
    capacity and its fixed operation and maintenance cost
  - **Operation terms**, which depend on the dispatch variables: the variable cost of
    producing energy

Every term is expressed in dollars of a single base year before it is added, which takes
three adjustments.

## From an overnight cost to a stream of payments

Capital costs in a `Portfolio` are overnight costs: the price of building one MW as if it
were paid for in full on the day it is built. Projects are not financed that way. The cost
is recovered over many years, at a rate of return that depends on how the project is
financed.

`PowerSystemsInvestments.jl` represents this by annualizing the overnight cost with a
capital recovery factor. The factor is computed from two properties of the technology's
financial data: its capital recovery period, and its weighted average cost of capital,
which reflects its mix of debt and equity. Multiplying the overnight cost by the factor
gives the equal yearly payment that recovers the investment over the recovery period.

That stream of yearly payments is then converted back into a single value at the time of
the investment, by discounting each payment at the discount rate of the `Portfolio`. When
the cost of capital of a technology is higher than the discount rate, the result is higher
than the overnight cost. This is how the financing terms of a technology affect its
competitiveness: two technologies with the same overnight cost are not equally attractive
if one is more expensive to finance.

## From different cost years to one

Cost data for different technologies is often quoted in dollars of different years. Each
technology's financial data records the year its costs are expressed in, and the
`Portfolio` records an inflation rate and a base year. Costs are converted to base-year
dollars using the inflation rate and the number of years between the two.

## From a future year to the present

A cost incurred in 2035 weighs less in the decision than the same cost incurred in 2030.
Every term is discounted from the year it occurs back to the base year of the `Portfolio`
at the discount rate:

  - A capital term is discounted from the first year of the investment period in which the
    capacity is built
  - An operation term is discounted from the year of the time step in which the energy is
    produced

Discounting is what lets the model weigh building early against building late. Building
later costs less in present value, but the capacity is not available to serve demand in
the meantime.

## Scaling operation costs

Operation is represented by a few representative periods, so the cost of a representative
hour has to be scaled to the amount of real time it stands for. Each operation term is
multiplied by the weight of its representative period. See
[Time Representation](@ref time_representation) for how weights are chosen.

Variable costs are in dollars per MWh and are applied to the power dispatched in each time
step, which assumes that time steps are one hour long.

## Where the financial inputs come from

| Input                                                    | Defined in                                  |
|:-------------------------------------------------------- |:------------------------------------------- |
| Base year, discount rate, inflation rate                 | The `Portfolio`                             |
| Capital recovery period, cost of capital, cost base year | Each technology's `TechnologyFinancialData` |
| Capital costs, fixed and variable operation costs        | Each technology                             |
| Investment periods                                       | [`DiscountedCashFlow`](@ref)                |
| Representative period weights                            | [`OperationalRepresentativeDays`](@ref)     |

!!! note
    
    [`DiscountedCashFlow`](@ref) also has `discount_rate` and `base_year` fields. The
    objective function currently takes the discount rate and base year from the
    `Portfolio`, not from these fields. Set them to the same values to avoid confusion.

## What is not included

The objective function is limited to the terms above. In particular, it does not include a
value for the capacity that remains at the end of the last investment period, costs for
retiring capacity, or a penalty for unserved demand. See
[Implementation Status](@ref implementation_status).
