abstract type AbstractTransportAggregation end

abstract type AbstractZonalTransportAggregation <: AbstractTransportAggregation end
struct SingleRegionBalanceModel <: AbstractZonalTransportAggregation end
struct MultiRegionBalanceModel <: AbstractZonalTransportAggregation end

abstract type AbstractNodalTransportAggregation <: AbstractTransportAggregation end
struct NodalBalanceModel <: AbstractNodalTransportAggregation end

"""
DC power flow between nodes using the power transfer distribution factors (PTDF) of the AC lines.
Each island of the network has one energy balance, and line flows are set by the injections at
every node.

How a `NodalACTransportTechnology` is modeled depends on its investment formulation:

  - `ContinuousInvestment` on a corridor (node pair) with existing capacity: the corridor is one
    branch, with the susceptance of its existing lines and a limit equal to their capacity plus
    the capacity built. Note that in this case the susceptance of the new line is not considered.
  - `ContinuousInvestment` on a corridor without existing capacity: the line is a branch of its
    own that is only in the network once it is built.
  - `IntegerInvestment` or `BinaryInvestment`: each unit is a branch of its own, in the network
    once built.

Branches that may not be built are removed with virtual transactions (Rahmani et al. 2016,
Mehrtash et al. 2020), which is exact for any set of unbuilt branches.

Settings, in the `attributes` of the `TransportModel`:

  - `"tol"`: PTDF entries at or below this magnitude are left out of the flows (default 0).
  - `"monitored"`: corridors whose flow is limited, by corridor name (its node names joined by
    `_`) or by the name of one of its technologies. All are monitored by default.

# Example

```julia
TransportModel(NodalPTDFModel; attributes=Dict{String, Any}("tol" => 1e-3))
```
"""
struct NodalPTDFModel <: AbstractNodalTransportAggregation end

# Network data computed when the model is built, such as the PTDF branches
abstract type AbstractNetworkData end

mutable struct TransportModel{T <: AbstractTransportAggregation}
    use_slacks::Bool
    attributes::Dict{String, Any}
    network_data::Union{Nothing, AbstractNetworkData}
    function TransportModel(
        ::Type{T};
        use_slacks=false,
        attributes=Dict{String, Any}(),
    ) where {T <: AbstractTransportAggregation}
        new{T}(use_slacks, attributes, nothing)
    end
end

get_use_slacks(m::TransportModel) = m.use_slacks
get_network_data(m::TransportModel) = m.network_data
