# PowerSystemsInvestments.jl

Investment modeling library for the Sienna ecosystem. Provides capacity expansion and other
investment models for power systems. Julia compat: `^1.10`.

## Data Models

- **PowerSystems.jl** — provides the core power system component data model (generators, buses, lines, etc.).
- **PowerInvestmentPortfolios.jl** — provides the investment portfolio data model (candidate technologies, investment options, etc.).

## Optimization Infrastructure

- **InfrastructureOptimizationModels.jl (IOM)** — supplies the optimization containers, model
  abstractions, variable/constraint/expression construction utilities, and other foundational types
  that this package builds on. PSI defines technology-specific investment formulations on top of the
  generic modeling layer provided by IOM.

> **General Sienna Programming Practices:** For information on performance requirements, code conventions, documentation practices, and contribution workflows that apply across all Sienna packages, see [Sienna.md](Sienna.md). Always
check this file before making plans, changes or running tests. Review in detail the testing proceedures at the beggining of every session.
