function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::ArgumentConstructStage,
    technology_model::TechnologyModel{T, B, C},
    # network_model::NetworkModel{<:PM.AbstractActivePowerModel},
) where {T <: PSIP.SupplyTechnology, B <: ContinuousInvestment, C <: BasicDispatch}

    #TODO: Port get_available_component functions from PSY
    devices = PSIP.get_technologies(T, p)

    # BuildCapacity variable
    add_variable!(container, BuildCapacity(), devices, B())

    # CumulativeCapacity
    add_expression!(container, CumulativeCapacity(), devices, B())

    #ActivePowerVariable
    add_variable!(container, ActivePowerVariable(), devices, C())

    # SupplyTotal
    #add_expression!(container, SupplyTotal(), devices, C())

    add_to_expression!(container, SupplyTotal(), devices, C())

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::ModelConstructStage,
    technology_model::TechnologyModel{T, B, C},
    # network_model::NetworkModel{<:PM.AbstractActivePowerModel},
) where {T <: PSIP.SupplyTechnology, B <: ContinuousInvestment, C <: BasicDispatch}
    devices = PSIP.get_technologies(T, p)

    # Capital Component of objective function
    objective_function!(container, devices, B())

    # Operations Component of objective function
    objective_function!(container, devices, C())

    # Add objective function from container to JuMP model
    update_objective_function!(container)

    # Capacity constraint
    add_constraints!(container, MaximumCumulativeCapacity(), CumulativeCapacity(), devices)

    # Dispatch constraint
    add_constraints!(
        container,
        ActivePowerLimitsConstraint(),
        ActivePowerVariable(),
        devices,
    )

    return
end
