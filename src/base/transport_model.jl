abstract type AbstractTransportAggregation end

abstract type AbstractZonalTransportAggregation <: AbstractTransportAggregation end
struct SingleRegionBalanceModel <: AbstractZonalTransportAggregation end
struct MultiRegionBalanceModel <: AbstractZonalTransportAggregation end

abstract type AbstractNodalTransportAggregation <: AbstractTransportAggregation end
struct NodalBalanceModel <: AbstractNodalTransportAggregation end

"""
DC power flow between nodes with the PTDF of the AC lines, and one energy balance per island.

Continuous lines on a corridor (node pair) with existing capacity form one branch, with the
susceptance of the existing lines and a limit that grows with the capacity built. A continuous
line on a new corridor, and each unit of an integer or binary line, is a branch that carries
flow only once built.

Attributes of the `TransportModel`:

  - `"monitored"`: corridors with flow limits, by corridor name (its node names joined by `_`)
    or line name (default: all).
  - `"flow_variables"`: limit a flow variable set equal to the PTDF flow instead of the PTDF
    expression (default `false`).
  - `"min_voltage"`: lines below this voltage (kV) are left out of the PTDF and dispatched like
    `BasicDispatch` lines under `NodalBalanceModel` (default 0).
  - `"relative_tol"`: leave out of a branch's flow the PTDF entries below this share of its
    largest entry (default 0; 1e-6 is safe). Reported flows use the whole PTDF. The big-M
    bounds of new corridors and unit lines assume exact corridor flows, so a large tolerance
    can make them too tight.
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
