abstract type AbstractTransportAggregation end

abstract type AbstractZonalTransportAggregation <: AbstractTransportAggregation end
struct SingleRegionBalanceModel <: AbstractZonalTransportAggregation end
struct MultiRegionBalanceModel <: AbstractZonalTransportAggregation end

abstract type AbstractNodalTransportAggregation <: AbstractTransportAggregation end
struct NodalBalanceModel <: AbstractNodalTransportAggregation end

"""
DC power flow between nodes using the PTDF of the AC lines, with one energy balance per
island.

Continuous lines on a corridor (node pair) with existing capacity form one branch whose
limit grows with the capacity built; its susceptance is that of the existing lines. A
continuous line on a new corridor, and each unit of an integer or binary line, is a branch
that only carries flow once built.

Attributes of the `TransportModel`:

  - `"tol"`: PTDF entries at or below this magnitude are left out of the flows (default 0).
  - `"monitored"`: corridors whose flow is limited, by corridor name (its node names joined
    by `_`) or by the name of one of its lines. All are monitored by default.
  - `"flow_variables"`: limit a flow variable set equal to the PTDF flow instead of the PTDF
    expression itself (default `false`).
"""
struct NodalPTDFModel <: AbstractNodalTransportAggregation end

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
