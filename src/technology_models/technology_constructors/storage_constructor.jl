function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::CapitalCostModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: PSIP.StorageTechnology,
    B <: ContinuousInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = metadata_string(technology_model)

    # BuildCapacity variables
    add_variable!(container, BuildEnergyCapacity(), devices, B(), tech_model)
    add_variable!(container, BuildPowerCapacity(), devices, B(), tech_model)

    # CumulativeCapacity expressions
    add_expression!(container, CumulativePowerCapacity(), devices, B(), tech_model)
    add_expression!(container, CumulativeEnergyCapacity(), devices, B(), tech_model)
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::CapitalCostModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: PSIP.StorageTechnology,
    B <: IntegerInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = metadata_string(technology_model)

    # BuildCapacity variables
    add_variable!(container, BuildEnergyCapacity(), devices, B(), tech_model)
    add_variable!(container, BuildPowerCapacity(), devices, B(), tech_model)

    # CumulativeCapacity expressions
    add_expression!(container, CumulativePowerCapacity(), devices, B(), tech_model)
    add_expression!(container, CumulativeEnergyCapacity(), devices, B(), tech_model)
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
) where {
    T <: PSIP.StorageTechnology,
    B <: InvestmentTechnologyFormulation,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = metadata_string(technology_model)

    #ActivePowerVariables
    add_variable!(container, ActiveInPowerVariable(), devices, C(), tech_model)
    add_variable!(container, ActiveOutPowerVariable(), devices, C(), tech_model)

    # EnergyVariable
    add_variable!(container, EnergyVariable(), devices, C(), tech_model)

    # EnergyBalance
    add_to_expression!(
        container,
        EnergyBalance(),
        ActiveInPowerVariable(),
        devices,
        C(),
        tech_model,
        transport_model,
    )
    add_to_expression!(
        container,
        EnergyBalance(),
        ActiveOutPowerVariable(),
        devices,
        C(),
        tech_model,
        transport_model,
    )

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
    T <: PSIP.StorageTechnology,
    B <: InvestmentTechnologyFormulation,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]
    tech_model = metadata_string(technology_model)

    #ActivePowerVariables
    #add_variable!(container, ActiveInPowerVariable(), devices, C(), tech_model)
    #add_variable!(container, ActiveOutPowerVariable(), devices, C(), tech_model)

    #EnergyVariable
    #add_variable!(container, EnergyVariable(), devices, C(), tech_model)

    # EnergyBalance
    add_to_expression!(
        container,
        FeasibilitySurplus(),
        ActiveInPowerVariable(),
        devices,
        D(),
        tech_model,
        transport_model,
    )
    add_to_expression!(
        container,
        FeasibilitySurplus(),
        ActiveOutPowerVariable(),
        devices,
        D(),
        tech_model,
        transport_model,
    )
    # add_to_expression!(container, DemandTotal(), devices, C())
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
    T <: PSIP.StorageTechnology,
    B <: InvestmentTechnologyFormulation,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = metadata_string(technology_model)

    # Capital Component of objective function
    objective_function!(container, devices, B(), tech_model)

    # Add objective function from container to JuMP model
    update_objective_function!(container)

    # Capacity constraints
    add_constraints!(
        container,
        MaximumCumulativePowerCapacity(),
        CumulativePowerCapacity(),
        devices,
        tech_model,
    )

    add_constraints!(
        container,
        MaximumCumulativeEnergyCapacity(),
        CumulativeEnergyCapacity(),
        devices,
        tech_model,
    )
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
    T <: PSIP.StorageTechnology,
    B <: InvestmentTechnologyFormulation,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = metadata_string(technology_model)

    # Operations Component of objective function
    objective_function!(container, devices, C(), tech_model)

    # Add objective function from container to JuMP model
    update_objective_function!(container)

    # Dispatch input power constraint
    add_constraints!(
        container,
        InputActivePowerVariableLimitsConstraint(),
        ActiveInPowerVariable(),
        devices,
        tech_model,
    )

    # Dispatch output power constraint
    add_constraints!(
        container,
        OutputActivePowerVariableLimitsConstraint(),
        ActiveOutPowerVariable(),
        devices,
        tech_model,
    )

    # Energy storage constraint
    add_constraints!(
        container,
        StateofChargeLimitsConstraint(),
        EnergyVariable(),
        devices,
        tech_model,
    )

    #State of charge constraint
    add_constraints!(
        container,
        EnergyBalanceConstraint(),
        EnergyVariable(),
        devices,
        tech_model,
    )

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
    T <: PSIP.StorageTechnology,
    B <: InvestmentTechnologyFormulation,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]
    tech_model = metadata_string(technology_model)

    return
end
