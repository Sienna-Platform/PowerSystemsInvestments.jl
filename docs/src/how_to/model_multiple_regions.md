# [Model Multiple Regions and Transmission](@id multi_region_how_to)

This guide shows how to balance supply and demand in several zones and let the model
invest in the transmission between them. For a complete worked example, see the tutorial
[Add Storage, Regions, and Transmission](@ref).

```julia
using PowerSystemsInvestments
using PowerSystemsInvestmentsPortfolios
using PowerSystems
```

## Step 1: Add the zones to the `Portfolio`

Create a `Zone` for each region and add it to the `Portfolio` before adding the
technologies located in it:

```julia
north = Zone(; name="North")
south = Zone(; name="South")
add_region!(portfolio, north)
add_region!(portfolio, south)
```

## Step 2: Assign each technology to one zone

Set the `region` of each supply, storage, and demand technology to a vector with a single
zone:

```julia
demand_south = DemandRequirement{PowerLoad}(;
    name="demand_south",
    power_systems_type="PowerLoad",
    available=true,
    region=[south],
)
add_technology!(portfolio, demand_south)
```

A technology that is assigned to no zone or to several zones causes the build to fail.

## Step 3: Add the transport technologies

Define an `AggregateTransportTechnology` for each pair of zones that can exchange energy,
with the zones it connects, its capital cost per MW, its capacity limits, and the fraction
of the flow that is lost:

```julia
line = AggregateTransportTechnology{ACBranch}(;
    name="north_south",
    power_systems_type="ACBranch",
    available=true,
    start_region=north,
    end_region=south,
    capital_costs=LinearCurve(400_000.0),
    capacity_limits=(min=0.0, max=1000.0),
    line_loss=0.03,
    financial_data=financials,
)
add_technology!(portfolio, line)
```

One technology represents the flow in both directions. A positive flow goes from the start
region to the end region.

## Step 4: Use a multi-region transport model

Create the template with a [`MultiRegionBalanceModel`](@ref):

```julia
template = InvestmentModelTemplate(
    capital,
    operations,
    feasibility,
    TransportModel(MultiRegionBalanceModel),
)
```

## Step 5: Assign formulations to the transport technologies

Add a technology model for the transport technologies, with
[`ContinuousInvestment`](@ref) and [`BasicDispatch`](@ref):

```julia
set_technology_model!(
    template,
    ["north_south"],
    AggregateTransportTechnology{ACBranch},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
```

Assign formulations to the other technologies as usual. See
[Assign Formulations to Technologies](@ref assign_formulations_how_to).

## Step 6: Read the transmission results

After solving the model, read the installed capacity of the transport technologies and the
flow in each time step:

```julia
const PSINV = PowerSystemsInvestments

capacity_key = PSINV.ExpressionKey(
    CumulativeCapacity,
    AggregateTransportTechnology{ACBranch},
    "ContinuousInvestment",
)
read_expression(model, capacity_key)

flow_key = PSINV.VariableKey(
    FlowActivePowerVariable,
    AggregateTransportTechnology{ACBranch},
    "BasicDispatch",
)
read_variable(model, flow_key)
```

## Compare with a single-region model

To measure the effect of transmission limits, solve the same `Portfolio` with a
[`SingleRegionBalanceModel`](@ref). Zones are ignored and every technology contributes to
one energy balance:

```julia
template = InvestmentModelTemplate(
    capital,
    operations,
    feasibility,
    TransportModel(SingleRegionBalanceModel),
)
```

Transport technologies have no effect on the energy balance of a single-region model.
Leave them out of the template so that the model does not consider building them.

### See also

  - [Energy Balance Formulations](@ref energy_balance_formulations)
  - [Transport Technology Formulations](@ref transport_formulations)
