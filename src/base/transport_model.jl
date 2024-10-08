abstract type AbstractTransportAggregation end

struct SingleRegionBalanceModel <: AbstractTransportAggregation end
struct MultiRegionBalanceModel <: AbstractTransportAggregation end
struct NodalBalanceModel <: AbstractTransportAggregation end

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
