# Developer Guidelines

In order to contribute to `PowerSystemsInvestments.jl`, it is required to follow the
conventions shared by all Sienna packages, which are maintained in
[`InfrastructureSystems.jl`](https://sienna-platform.github.io/InfrastructureSystems.jl/stable/):

  - The [style guide](https://sienna-platform.github.io/InfrastructureSystems.jl/stable/style/)
    for the code
  - The [documentation best practices](https://sienna-platform.github.io/InfrastructureSystems.jl/stable/docs_best_practices/explanation/)
    for the documentation

## Running the tests

```sh
julia --project=test test/runtests.jl
```

To run a single test file, pass its name without the extension:

```sh
julia --project=test -e 'push!(ARGS, "test_model"); include("test/runtests.jl")'
```

## Formatting the code

```sh
julia scripts/formatter/formatter_code.jl
```

Run the formatter from the root of the repository before opening a pull request. It
formats the source code and the markdown files of the documentation.

## Building the documentation

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The documentation must build without errors. Missing docstrings, broken cross-references,
and failing tutorial code are all errors.

The documentation follows the [Diataxis](https://diataxis.fr/) framework and the
[Sienna documentation best practices](https://sienna-platform.github.io/InfrastructureSystems.jl/stable/docs_best_practices/explanation/):

  - Tutorials are [`Literate.jl`](https://fredrikekre.github.io/Literate.jl/v2/) scripts in
    `docs/src/tutorials`. They are converted to markdown pages and Jupyter notebooks, and
    their code is run when the documentation is built.
  - How-to guides, explanation pages, and reference pages are markdown files in
    `docs/src/how_to`, `docs/src/explanation`, `docs/src/api`, and
    `docs/src/formulation_library`.
  - Every exported type and function needs a docstring. Docstrings are collected in the
    [Public API Reference](@ref) by source file.

## Adding a formulation

A formulation is a type and a set of methods that are selected by the technology type and
the formulation type together. To add one:

 1. Define the formulation type as a subtype of
    [`InvestmentTechnologyFormulation`](@ref),
    [`OperationsTechnologyFormulation`](@ref), or
    [`FeasibilityTechnologyFormulation`](@ref), with a docstring, and export it.
 2. Define any new variable, expression, and constraint types in `src/base`.
 3. Add `construct_technologies!` methods for the technology type and the formulation in
    `src/technology_models/technology_constructors`: one for the argument stage, which
    creates variables and expressions, and one for the model stage, which adds cost terms
    and constraints. See [How a Model is Built](@ref build_process).
 4. Add the methods those constructors call, such as `add_constraints!`, in
    `src/technology_models/technologies`.
 5. Add a test that builds and solves a model with the formulation.
 6. Document the formulation in the [Formulation Library](@ref formulation_library_intro)
    and add it to the table of valid combinations.
