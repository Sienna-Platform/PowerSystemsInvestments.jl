function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::CapitalCostModel,
    technology_model::TechnologyModel{T,B,C,D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T<:PSIP.DemandRequirement,
    B<:StaticLoadInvestment,
    C<:BasicDispatch,
    D<:FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::OperationCostModel,
    technology_model::TechnologyModel{T,B,C,D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    # network_model::NetworkModel{<:PM.AbstractActivePowerModel},
) where {
    T<:PSIP.DemandRequirement,
    B<:StaticLoadInvestment,
    C<:BasicDispatch,
    D<:FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    devices = [PSIP.get_technology(T, p, n) for n in names]
    tech_model = metadata_string(technology_model)
    # EnergyBalance
    add_to_expression!(container, EnergyBalance(), devices, C(), tech_model, transport_model)

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::FeasibilityModel,
    technology_model::TechnologyModel{T,B,C,D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T<:PSIP.DemandRequirement,
    B<:StaticLoadInvestment,
    C<:BasicDispatch,
    D<:FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]
    tech_model = metadata_string(technology_model)
    add_to_expression!(container, CapacitySurplus(), devices, D(), tech_model, transport_model)
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::CapitalCostModel,
    technology_model::TechnologyModel{T,B,C,D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T<:PSIP.DemandRequirement,
    B<:StaticLoadInvestment,
    C<:BasicDispatch,
    D<:FeasibilityTechnologyFormulation,
}

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::OperationCostModel,
    technology_model::TechnologyModel{T,B,C,D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T<:PSIP.DemandRequirement,
    B<:StaticLoadInvestment,
    C<:BasicDispatch,
    D<:FeasibilityTechnologyFormulation,
}

    #power balance
    #add_constraints!(container, SupplyDemandBalance, T)

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::FeasibilityModel,
    technology_model::TechnologyModel{T,B,C,D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T<:PSIP.DemandRequirement,
    B<:StaticLoadInvestment,
    C<:BasicDispatch,
    D<:FeasibilityTechnologyFormulation,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]
    attributes = technology_model.attributes
    tech_model = metadata_string(technology_model)
    if attributes["planning_reserve_margin"]
        add_constraints!(
            container,
            p,
            PlanningReserveMarginConstraint(),
            devices,
            tech_model
        )
    end

    if attributes["capacity_credit"] == "nd"
        add_constraints!(
            container,
            p,
            CCNDSurfaceConstraint(),
            devices,
            tech_model
        )
    end

    return
end
