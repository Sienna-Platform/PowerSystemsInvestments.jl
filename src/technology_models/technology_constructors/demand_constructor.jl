function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::CapitalCostModel,
    tech_type::Type{T},
    tech_formulation::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {T <: PSIP.DemandRequirement, B <: StaticLoadInvestment, X <: TechnologyModel}
    # Do Nothing. No Load Investment allowed.
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::OperationCostModel,
    tech_type::Type{T},
    tech_formulation::Type{C},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {T <: PSIP.DemandRequirement, C <: BasicDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # EnergyBalance
    add_to_expression!(container, EnergyBalance(), devices, C(), transport_model)

    # WeightedEnergyDemand
    add_to_expression!(container, WeightedEnergyDemand(), devices, C(), transport_model)

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::FeasibilityModel,
    tech_type::Type{T},
    tech_formulation::Type{D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.DemandRequirement,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]
    add_to_expression!(container, FeasibilitySurplus(), devices, D(), transport_model)
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::CapitalCostModel,
    tech_type::Type{T},
    tech_formulation::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {T <: PSIP.DemandRequirement, B <: StaticLoadInvestment, X <: TechnologyModel}
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::OperationCostModel,
    tech_type::Type{T},
    tech_formulation::Type{C},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {T <: PSIP.DemandRequirement, C <: BasicDispatch, X <: TechnologyModel}
    # Do nothing for loads
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::FeasibilityModel,
    tech_type::Type{T},
    tech_formulation::Type{D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.DemandRequirement,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    # Do nothing for loads
    return
end
