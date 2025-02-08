function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::CapitalCostModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: PSIP.DemandRequirement,
    B <: StaticLoadInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    # Do Nothing. No Load Investment allowed.
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::OperationCostModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    # network_model::NetworkModel{<:PM.AbstractActivePowerModel},
) where {
    T <: PSIP.DemandRequirement,
    B <: StaticLoadInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # EnergyBalance
    add_to_expression!(container, EnergyBalance(), devices, C(), transport_model)

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::FeasibilityModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: PSIP.DemandRequirement,
    B <: StaticLoadInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
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
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: PSIP.DemandRequirement,
    B <: StaticLoadInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::OperationCostModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: PSIP.DemandRequirement,
    B <: StaticLoadInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    # Do nothing for loads
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::FeasibilityModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: PSIP.DemandRequirement,
    B <: StaticLoadInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    # Do nothing for loads
    return
end
