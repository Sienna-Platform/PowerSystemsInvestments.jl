# Public API Reference

```@meta
CurrentModule = PowerSystemsInvestments
```

```@contents
Pages = ["public.md"]
Depth = 2
```

## Investment Model

```@autodocs
Modules = [PowerSystemsInvestments]
Pages   = ["investment_model.jl", "investment_problem_results.jl", "solution_algorithms.jl", "SingleInstanceSolve.jl", "serialization.jl", "single_optimization_container.jl"]
Order = [:type, :function]
Public = true
Private = false
```

## Template

```@autodocs
Modules = [PowerSystemsInvestments]
Pages   = ["investment_model_template.jl", "technology_model.jl", "requirement_model.jl", "transport_model.jl"]
Order = [:type, :function]
Public = true
Private = false
```

## Capital, Operation, and Feasibility Models

```@autodocs
Modules = [PowerSystemsInvestments]
Pages   = ["capital_models.jl", "operation_model.jl", "feasibility_model.jl"]
Order = [:type, :function]
Public = true
Private = false
```

## Technology Formulations

For the equations behind each formulation, see the
[Formulation Library](@ref formulation_library_intro).

### Investment Formulations

```@autodocs
Modules = [PowerSystemsInvestments]
Pages   = ["technology_capital_formulations.jl"]
Order = [:type, :function]
Public = true
Private = false
```

### Operations and Feasibility Formulations

```@autodocs
Modules = [PowerSystemsInvestments]
Pages   = ["technology_operation_formulations.jl"]
Order = [:type, :function]
Public = true
Private = false
```

### Requirement Formulations

```@autodocs
Modules = [PowerSystemsInvestments]
Pages   = ["requirement_formulations.jl"]
Order = [:type, :function]
Public = true
Private = false
```

## Variables

```@autodocs
Modules = [PowerSystemsInvestments]
Pages   = ["variables.jl"]
Order = [:type, :function]
Public = true
Private = false
```

## Expressions

```@autodocs
Modules = [PowerSystemsInvestments]
Pages   = ["expressions.jl"]
Order = [:type, :function]
Public = true
Private = false
```

## Constraints

```@autodocs
Modules = [PowerSystemsInvestments]
Pages   = ["constraints.jl"]
Order = [:type, :function]
Public = true
Private = false
```
