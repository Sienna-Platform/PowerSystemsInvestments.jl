# PowerSystemsInvestments.jl

[![main - CI](https://github.com/NREL-Sienna/PowerSystemsInvestments.jl/workflows/main%20-%20CI/badge.svg)](https://github.com/NREL-Sienna/PowerSystemsInvestments.jl/actions/workflows/main-tests.yml)
[![codecov](https://codecov.io/gh/NREL-Sienna/PowerSystemsInvestments.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/NREL-Sienna/PowerSystemsInvestments.jl)
[![Documentation Build](https://github.com/NREL-Sienna/PowerSystemsInvestments.jl/workflows/Documentation/badge.svg?)](https://nrel-sienna.github.io/PowerSystemsInvestments.jl/stable)
[<img src="https://img.shields.io/badge/slack-@Sienna/PSINV.svg?logo=slack">](https://join.slack.com/t/nrel-sienna/shared_invite/zt-glam9vdu-o8A9TwZTZqqNTKHa7q3BpQ)
[![PowerSystemsInvestments.jl Downloads](https://shields.io/endpoint?url=https://pkgs.genieframework.com/api/v1/badge/PowerSystemsInvestments)](https://pkgs.genieframework.com?packages=PowerSystemsInvestments)

`PowerSystemsInvestments.jl` is a Julia package for formulating and solving capacity expansion problems: deciding which generation, storage, and transmission capacity to build, and when, to meet demand at the lowest cost. It is part of the [Sienna](https://github.com/Sienna-Platform/Sienna) ecosystem.

The package is under active development and has not had a stable release yet.

## Overview

An investment model is built from two inputs:

  - A `Portfolio`, defined with [`PowerSystemsInvestmentsPortfolios.jl`](https://github.com/Sienna-Platform/PowerSystemsInvestmentsPortfolios.jl), which holds the data: candidate and existing technologies, their costs, regions, and time series
  - An `InvestmentModelTemplate`, which holds the modeling choices: investment periods, representative days, how regions are balanced, and the formulation used for each technology

```julia
template = InvestmentModelTemplate(capital, operations, feasibility, TransportModel(SingleRegionBalanceModel))
set_technology_model!(
    template,
    ["gas_cc"],
    SupplyTechnology{ThermalStandard},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)

model = InvestmentModel(template, SingleInstanceSolve, portfolio; optimizer=HiGHS.Optimizer)
build!(model; output_dir="results")
solve!(model)
```

## Documentation

The documentation is in [`docs/src`](docs/src) and follows the [Diataxis](https://diataxis.fr/) framework: tutorials, how-to guides, explanation, and reference, including a formulation library with the equations of each formulation. Start with the tutorial `docs/src/tutorials/first_capacity_expansion.jl`.

To build it locally:

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

## Development

Contributions to the development and enhancement of `PowerSystemsInvestments.jl` are welcome. Please see [CONTRIBUTING.md](https://github.com/Sienna-Platform/PowerSystemsInvestments.jl/blob/main/CONTRIBUTING.md) for code contribution guidelines.

## License

`PowerSystemsInvestments.jl` is released under a BSD [license](https://github.com/Sienna-Platform/PowerSystemsInvestments.jl/blob/main/LICENSE). It has been developed as part of the [Sienna platform](https://www.nlr.gov/analysis/sienna.html) by the U.S. Department of Energy's National Laboratory of the Rockies ([NLR](https://www.nlr.gov/), formerly NREL).
