# [Define Investment Periods and Representative Days](@id time_structure_how_to)

This guide shows how to define when capacity can be built and which periods represent the
operation of the system. See [Time Representation](@ref time_representation) for the
concepts behind these choices.

```julia
using PowerSystemsInvestments
using Dates
```

## Step 1: Define the investment periods

Define each investment period as a tuple of its first and last dates, in chronological
order, and pass them to a [`DiscountedCashFlow`](@ref):

```julia
investment_periods = [
    (Date(2030, 1, 1), Date(2034, 12, 31)),
    (Date(2035, 1, 1), Date(2039, 12, 31)),
    (Date(2040, 1, 1), Date(2044, 12, 31)),
]
capital = DiscountedCashFlow(0.07, Year(2025), investment_periods)
```

Capital costs are discounted from the year of the first date of each period.

## Step 2: Define the representative periods

Define each representative period as a vector of consecutive time stamps. Every period
must fall inside one of the investment periods:

```julia
winter_2030 = collect(DateTime(2030, 1, 15, 0):Hour(1):DateTime(2030, 1, 15, 23))
summer_2030 = collect(DateTime(2030, 7, 15, 0):Hour(1):DateTime(2030, 7, 15, 23))
winter_2035 = collect(DateTime(2035, 1, 15, 0):Hour(1):DateTime(2035, 1, 15, 23))
summer_2035 = collect(DateTime(2035, 7, 15, 0):Hour(1):DateTime(2035, 7, 15, 23))
winter_2040 = collect(DateTime(2040, 1, 15, 0):Hour(1):DateTime(2040, 1, 15, 23))
summer_2040 = collect(DateTime(2040, 7, 15, 0):Hour(1):DateTime(2040, 7, 15, 23))

representative_periods =
    [winter_2030, summer_2030, winter_2035, summer_2035, winter_2040, summer_2040]
```

List the periods in chronological order. The position of a period in this vector is the
`"rep_day"` used to tag its time series.

## Step 3: Define the weights

Give each representative period a weight equal to the number of real periods it stands
for. Here, each day represents half of the days of a five-year investment period:

```julia
weights = fill(365.0 * 5 / 2, length(representative_periods))
operations = OperationalRepresentativeDays(representative_periods, weights)
```

The weights of the periods in an investment period should add up to the number of days in
that investment period.

## Step 4: Add the time series to the `Portfolio`

Each technology that needs a time series needs one for every representative period,
tagged with the year of the period and its position in `representative_periods`. For a
demand technology named `demand` with a vector of 24 hourly values for each period in
`demand_values`:

```julia
using PowerSystemsInvestmentsPortfolios
using PowerSystems
using TimeSeries
const PSIP = PowerSystemsInvestmentsPortfolios

for (rep_day, period) in enumerate(representative_periods)
    time_series = SingleTimeSeries("ops_demand", TimeArray(period, demand_values[rep_day]))
    PSIP.add_time_series!(
        portfolio,
        demand,
        time_series;
        features=Dict("year" => string(year(first(period))), "rep_day" => rep_day),
    )
end
```

See [Time Series Names](@ref time_series_names) for the name each technology type expects.

## Step 5: Create the template

Pass the capital and operation models to the [`InvestmentModelTemplate`](@ref), with a
feasibility model that has no periods:

```julia
feasibility = RepresentativePeriods(Vector{Vector{DateTime}}())
template = InvestmentModelTemplate(
    capital,
    operations,
    feasibility,
    TransportModel(SingleRegionBalanceModel),
)
```

## Use time steps that are not hourly

Storage formulations take the length of the time steps from the first two time stamps of
each representative period, so a period can use a different resolution:

```julia
winter_2030 = collect(DateTime(2030, 1, 15, 0):Hour(4):DateTime(2030, 1, 15, 20))
```

!!! warning
    
    Variable operation costs are not scaled by the length of the time step. With time
    steps that are not one hour long, multiply the weights by the length of the time step
    in hours.
