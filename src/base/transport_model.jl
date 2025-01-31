abstract type AbstractTransportAggregation end

struct SingleRegionBalanceModel <: AbstractTransportAggregation end
struct MultiRegionBalanceModel <: AbstractTransportAggregation end
struct NodalBalanceModel <: AbstractTransportAggregation end

mutable struct TransportModel{T<:AbstractTransportAggregation}
    use_slacks::Bool
    attributes::Dict{String,Any}

    function TransportModel(
        ::Type{T};
        use_slacks=false,
        attributes=Dict{String,Any}("risk_curve" => false),
    ) where {T<:AbstractTransportAggregation}
        new{T}(use_slacks, attributes)
    end
end

get_use_slacks(m::TransportModel) = m.use_slacks
