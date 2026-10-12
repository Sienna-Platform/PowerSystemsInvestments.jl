# [Time Representation](@id time_representation)

A capacity expansion problem spans decades, but the operation of a power system has to be
checked hour by hour. Modeling every hour of every year would make the problem too large
to solve. `PowerSystemsInvestments.jl` handles this with two time scales, and a mapping
between them.

## Two time scales

**Investment periods** are the points at which capacity can be built. Each is a span of
dates, such as 2030 to 2034. They are defined by the capital cost model of the template,
for example in the `investment_years` of a [`DiscountedCashFlow`](@ref). Build variables
have one value per investment period.

**Operational periods** are short stretches of consecutive time steps, typically a day of
24 hours, that stand in for the operation of the system during an investment period. They
are defined by the operation cost model, for example in the `representative_series` of an
[`OperationalRepresentativeDays`](@ref). Dispatch variables have one value per time step.

```
investment periods    │────────── 1: 2030–2034 ──────────│────────── 2: 2035–2039 ──────────│

operational periods         ┌─ day 1 ─┐                        ┌─ day 2 ─┐
                            │ 24 hours │                        │ 24 hours │
                            └──────────┘                        └──────────┘

time steps                   1 ...... 24                         25 ..... 48
```

## How the two are linked

Each operational period belongs to the investment period that contains its dates. An
operational period that does not fall inside any investment period is an error.

This mapping is what connects investment to operation. In every time step of an
operational period, a technology is limited by the capacity installed up to and including
the investment period that the operational period belongs to. Capacity built in the second
investment period is available in the representative days of the second period, and not in
those of the first.

An investment period can contain several operational periods, for example a winter day and
a summer day. All of them see the same installed capacity.

## Weights

A representative day stands for many real days, so its costs and energy have to be scaled
up. Each operational period has a weight, given in the `series_weights` of
[`OperationalRepresentativeDays`](@ref), which multiplies:

  - The variable operation costs of the period in the objective function
  - The energy generated and consumed in the period, wherever energy is totaled, such as
    in an energy share requirement

If one day represents a full year of a five-year investment period, its weight is
`365 * 5`. If a winter day and a summer day each represent half of the year, each has a
weight of `365 * 5 / 2`.

The weights are what make the trade-off between capital and operation costs meaningful.
Capital costs are paid once per unit of capacity; operation costs are counted for a few
representative hours. Without weights, operation costs would be understated by orders of
magnitude and the model would under-invest in technologies that are expensive to build but
cheap to run.

## Time indices in variables and results

All operational periods are laid end to end and their time steps are numbered
consecutively, in the order the periods are listed. With two representative days of 24
hours, time steps 1 to 24 are the first day and 25 to 48 are the second. Investment
periods are numbered separately, starting at 1.

Results use these indices. The `time_index` column of a result is an investment period
number for investment variables and expressions, and a time step number for operations
variables. A few expressions that total energy over a representative period are indexed by
the number of the operational period instead.

## Chronology between operational periods

Representative days are samples, so two consecutive time steps in the model are not always
consecutive in reality: time step 24 is the last hour of one representative day and time
step 25 is the first hour of a different day, possibly years later. This matters for any
constraint that links one time step to the next, and above all for storage, where the
energy stored at the end of one hour is the starting point for the next.

`PowerSystemsInvestments.jl` leaves the treatment of that boundary to the operations
formulation, because there is no single right answer:

  - [`CyclicalStorageDispatch`](@ref) treats each representative period as a closed loop.
    The first time step follows from the last time step of the same period, so the storage
    ends each period where it started. This suits short-duration storage and independent
    sample days.
  - [`ChronologicalStorageDispatch`](@ref) treats the representative periods of an
    investment period as a sequence. Stored energy carries over from the end of one period
    to the start of the next, and starts from zero in the first period of each investment
    period. This suits periods that are chosen to be consecutive.

## Time series follow the same structure

The time series in a `Portfolio` are stored per operational period. A technology has one
series for each period, tagged with the year of the period and with the position of the
period in the list of operational periods. When a model is built, each formulation
retrieves the series for each period by those tags. See
[Time Series Names](@ref time_series_names) for the names and tags that are expected.

## Feasibility periods

The template also holds a feasibility model, such as [`RepresentativePeriods`](@ref), with
its own list of periods. The intent is to test the investment plan against conditions that
are not part of the cost calculation, such as a peak-demand day: feasibility periods
constrain what must be built without contributing operation costs to the objective. They
are mapped to investment periods in the same way as operational periods and their time
steps are numbered after all of the operational time steps.

!!! note
    
    Feasibility periods are only partly implemented. See
    [Implementation Status](@ref implementation_status).
