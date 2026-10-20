abstract type AbstractTransportAggregation end

abstract type AbstractZonalTransportAggregation <: AbstractTransportAggregation end
struct SingleRegionBalanceModel <: AbstractZonalTransportAggregation end
struct MultiRegionBalanceModel <: AbstractZonalTransportAggregation end

abstract type AbstractNodalTransportAggregation <: AbstractTransportAggregation end
struct NodalBalanceModel <: AbstractNodalTransportAggregation end
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
