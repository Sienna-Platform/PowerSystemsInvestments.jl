function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::ArgumentConstructStage,
    model::CapitalCostModel,
    technology_model::TechnologyModel{T, B, C},
    # network_model::NetworkModel{<:PM.AbstractActivePowerModel},
) where {T <: PSIP.DemandRequirement, B <: StaticLoadInvestment, C <: BasicDispatch}

    #TODO: Port get_available_component functions from PSY
    devices = PSIP.get_technologies(T, p)

    # SupplyTotal, initialize expression, then add ActivePowerVariable in supply_constructor
    add_expression!(container, SupplyTotal(), devices, C())

    # DemandTotal
    add_expression!(container, DemandTotal(), devices, C())

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::ModelConstructStage,
    technology_model::TechnologyModel{T, B, C},
    # network_model::NetworkModel{<:PM.AbstractActivePowerModel},
) where {T <: PSIP.DemandRequirement, B <: StaticLoadInvestment, C <: BasicDispatch}

    #power balance
    add_constraints!(container, SupplyDemandBalance, T)

    return
end
