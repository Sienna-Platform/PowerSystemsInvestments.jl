# [Add an Energy Share Requirement](@id energy_share_how_to)

This guide shows how to require that a set of technologies supplies at least a fraction of
the demand, as in a renewable portfolio standard.

It assumes you have a `Portfolio` named `portfolio` that contains a wind technology named
`"wind"` and a demand named `"demand"`, and a template named `template`.

```julia
using PowerSystemsInvestments
using PowerSystemsInvestmentsPortfolios
using PowerSystems
const PSIP = PowerSystemsInvestmentsPortfolios
```

## Step 1: Define the requirement

Create an `EnergyShareRequirements` with the fraction of the demand that must be supplied
and a year in the investment period it applies to:

```julia
wind_share = EnergyShareRequirements(;
    name="wind_share",
    available=true,
    target_year=2030,
    generation_fraction_requirement=0.3,
)
PSIP.add_requirement!(portfolio, wind_share)
```

The requirement applies to the investment period that contains the target year. The build
fails if no investment period contains it.

## Step 2: Attach the requirement to the contributing technologies

A requirement does not list the technologies it applies to. Each technology lists the
requirements it contributes to. Attach the requirement to the technologies whose generation
counts toward it:

```julia
wind = PSIP.get_technology(SupplyTechnology{RenewableDispatch}, portfolio, "wind")
PSIP.set_requirements!(wind, [wind_share])
```

Then attach it to the demands that the fraction is measured against:

```julia
demand = PSIP.get_technology(DemandRequirement{PowerLoad}, portfolio, "demand")
PSIP.set_requirements!(demand, [wind_share])
```

A requirement needs at least one available contributing technology on each side.

!!! note
    
    `set_requirements!` replaces the requirements of a technology. To add a requirement to
    a technology that already has some, pass the full list.

## Step 3: Add a requirement model to the template

Assign the [`RequirementEnergyShare`](@ref) formulation to the requirement by name with
[`set_requirement_model!`](@ref):

```julia
set_requirement_model!(
    template,
    ["wind_share"],
    EnergyShareRequirements,
    RequirementEnergyShare,
)
```

Every contributing supply, storage, or co-located technology must also have a technology
model in the template.

## Step 4: Check the requirement in the results

After solving the model, read the weighted generation and the weighted demand of the
requirement in each representative period:

```julia
const PSINV = PowerSystemsInvestments

generation_key = PSINV.ExpressionKey(WeightedEnergyShareGeneration, EnergyShareRequirements)
generation = read_expression(model, generation_key)

demand_key = PSINV.ExpressionKey(WeightedEnergyShareDemand, EnergyShareRequirements)
demand_energy = read_expression(model, demand_key)
```

In these results, `name` is the name of the requirement and `time_index` is the number of
the representative period. The requirement compares the sums over the representative
periods of the target investment period.

## Apply a share in several investment periods

A requirement applies to one investment period. To apply a share in each investment
period, add one requirement for each, with a target year in that period, and attach all of
them to the contributing technologies:

```julia
share_2030 = EnergyShareRequirements(;
    name="share_2030",
    available=true,
    target_year=2030,
    generation_fraction_requirement=0.3,
)
share_2035 = EnergyShareRequirements(;
    name="share_2035",
    available=true,
    target_year=2035,
    generation_fraction_requirement=0.5,
)
PSIP.add_requirement!(portfolio, share_2030)
PSIP.add_requirement!(portfolio, share_2035)
PSIP.set_requirements!(wind, [share_2030, share_2035])
PSIP.set_requirements!(demand, [share_2030, share_2035])

set_requirement_model!(
    template,
    ["share_2030"],
    EnergyShareRequirements,
    RequirementEnergyShare,
)
set_requirement_model!(
    template,
    ["share_2035"],
    EnergyShareRequirements,
    RequirementEnergyShare,
)
```

Add each requirement with its own call to [`set_requirement_model!`](@ref).

### See also

  - [Requirement Formulations](@ref requirement_formulations)
