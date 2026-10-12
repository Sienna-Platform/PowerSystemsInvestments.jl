"""
Abstract supertype for the ways energy balances are aggregated across the portfolio.
"""
abstract type AbstractTransportAggregation end

"""
Transport formulation with a single energy balance for the whole portfolio. Transport
technologies are not represented.
"""
struct SingleRegionBalanceModel <: AbstractTransportAggregation end
"""
Transport formulation with one energy balance for each `Zone` in the portfolio. Zones
exchange energy through `AggregateTransportTechnology` technologies.
"""
struct MultiRegionBalanceModel <: AbstractTransportAggregation end
"""
Transport formulation with one energy balance for each `Node` in the portfolio. Nodes
exchange energy through `NodalACTransportTechnology` technologies.
"""
struct NodalBalanceModel <: AbstractTransportAggregation end

"""
Establishes how energy balances are formulated, specified by an
[`AbstractTransportAggregation`](@ref) type.

# Arguments

  - `::Type{T}`: Transport formulation, e.g. [`SingleRegionBalanceModel`](@ref)
  - `use_slacks::Bool = false`: Reserved for adding slack variables to the energy balance.
    Not used yet.

# Example

```julia
transport = TransportModel(MultiRegionBalanceModel)
```
"""
mutable struct TransportModel{T <: AbstractTransportAggregation}
    use_slacks::Bool
    function TransportModel(
        ::Type{T};
        use_slacks=false,
    ) where {T <: AbstractTransportAggregation}
        new{T}(use_slacks)
    end
end

get_use_slacks(m::TransportModel) = m.use_slacks
