# Welcome to PowerSystemsInvestments.jl

```@meta
CurrentModule = PowerSystemsInvestments
```

!!! warning "Under active development"
    
    `PowerSystemsInvestments.jl` has not had a stable release yet. Interfaces can change
    without notice, and some features that appear in the API are not implemented. See
    [Implementation Status](@ref implementation_status) for what works today.

## About

`PowerSystemsInvestments.jl` is a [`Julia`](http://www.julialang.org) package for
formulating and solving capacity expansion problems: deciding which generation, storage,
and transmission capacity to build, and when, to meet demand at the lowest cost.

`PowerSystemsInvestments.jl` builds an optimization problem with
[`JuMP.jl`](https://jump.dev/JuMP.jl/stable/) from two inputs:

  - A `Portfolio`, defined with
    [`PowerSystemsInvestmentsPortfolios.jl`](https://sienna-platform.github.io/PowerSystemsInvestmentsPortfolios.jl/stable/),
    which holds the data: the candidate and existing technologies, their costs, the regions
    they are in, and their time series
  - An [`InvestmentModelTemplate`](@ref), which holds the modeling choices: how costs are
    accounted for, how time and space are represented, and which formulation applies to
    each technology

Keeping the data separate from the modeling choices makes it possible to solve the same
portfolio under different formulations, for example with continuous or integer build
decisions, or with one region or many, without changing the data.

`PowerSystemsInvestments.jl` is part of the National Laboratory of the Rockies'
[Sienna ecosystem](https://www.nlr.gov/analysis/sienna.html), an open source framework for
power system modeling, simulation, and optimization. The Sienna ecosystem can be
[found on GitHub](https://github.com/Sienna-Platform/Sienna). It contains three
applications:

  - [Sienna\Data](https://github.com/Sienna-Platform/Sienna?tab=readme-ov-file#siennadata)
    enables efficient data input, analysis, and transformation
  - [Sienna\Ops](https://github.com/Sienna-Platform/Sienna?tab=readme-ov-file#siennaops)
    enables system scheduling simulations by formulating and solving optimization problems
  - [Sienna\Dyn](https://github.com/Sienna-Platform/Sienna?tab=readme-ov-file#siennadyn)
    enables system transient analysis including small signal stability and full system
    dynamic simulations

Each application uses multiple packages in the [`Julia`](http://www.julialang.org)
programming language.

## How To Use This Documentation

There are four main sections containing different information:

  - **Tutorials** - Detailed walk-throughs to help you *learn* how to use
    `PowerSystemsInvestments.jl`
  - **How to...** - Directions to help *guide* your work for a particular task
  - **Explanation** - Additional details and background information to help you *understand*
    `PowerSystemsInvestments.jl`, its structure, and how it works behind the scenes
  - **Reference** - Technical references and API for a quick *look-up* during your work,
    including the Formulation Library with the variables and equations behind each
    formulation

`PowerSystemsInvestments.jl` strives to follow the [Diataxis](https://diataxis.fr/)
documentation framework.

If you are new to `PowerSystemsInvestments.jl`, start with the tutorial
[Build and Solve a Capacity Expansion Model](@ref).

## Installation and Quick Links

  - [Sienna installation page](https://sienna-platform.github.io/Sienna/SiennaDocs/docs/build/how-to/install/):
    Instructions to install `PowerSystemsInvestments.jl` and other Sienna packages
  - [`JuMP.jl` solver's page](https://jump.dev/JuMP.jl/stable/installation/#Install-a-solver):
    An optimization solver is required to solve a model. Refer to this page to select and
    install a solver for your application.
  - [`PowerSystemsInvestmentsPortfolios.jl` documentation](https://sienna-platform.github.io/PowerSystemsInvestmentsPortfolios.jl/stable/):
    How to define the `Portfolio` that an investment model is built from
  - [Sienna Documentation Hub](https://sienna-platform.github.io/Sienna/SiennaDocs/docs/build/index.html):
    Links to other Sienna packages' documentation
