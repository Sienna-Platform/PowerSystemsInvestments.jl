function construct_device!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::ArgumentConstructStage,
    model::AbstractTechnologyFormulation, #::DeviceModel{R,D}
    network_model, #::NetworkModel
) # where { R <: ..., D <: ... } 

    # Build Capacity for SupplyTechnology
    devices = PSIP.get_technologies(SupplyTechnology, p)

    add_variable!(container, BuildCapacity(), devices, model) #D()

    #Total Capacity for SupplyTechnology

    add_expression!(container, CumulativeCapacity(), devices, model)
end

function construct_device!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::ModelConstructStage,
    model::AbstractTechnologyFormulation, #::DeviceModel{R, <:AbstractRenewableDispatchFormulation},
    network_model, #::NetworkModel{<:PM.AbstractPowerModel},
) #where {R <: PSY.RenewableGen}

    # Maximum constraint for SupplyTechnology
    devices = PSIP.get_technologies(SupplyTechnology, p)

    add_constraints!(
        container,
        MaximumCumulativeCapacity,
        CumulativeCapacity(),
        devices,
        model,
    )

    #Thermal dispatch
    devices = PSIP.get_technologies(SupplyTechnology{ThermalStandard}, p)

    add_constraints!(
        container,
        ActivePowerLimitsConstraint,
        ActivePowerVariable(),
        devices,
        model,
        network_model,
    )

    #Renewable
    devices = PSIP.get_technologies(SupplyTechnology{RenewableDispatch}, p)

    add_constraints!(
        container,
        ActivePowerVariableLimitsConstraint,
        ActivePowerVariable(),
        devices,
        model,
        network_model,
    )
end
