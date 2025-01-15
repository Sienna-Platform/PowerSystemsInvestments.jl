function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::CapitalCostModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: GenericTransportTechnology,
    B <: ContinuousInvestment,
    C <: OperationsTechnologyFormulation,
    D <: FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    #TODO: Review when we start working with larger models
    devices = [PSIP.get_technology(T, p, n) for n in names]
    #PSIP.get_technologies(T, p)

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    # BuildCapacity variable
    add_variable!(container, BuildCapacity(), devices, B(), tech_model)

    # CumulativeCapacity
    add_expression!(container, CumulativeCapacity(), devices, B(), tech_model, transport_model)

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::OperationCostModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: GenericTransportTechnology,
    B <: ContinuousInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    #ActivePowerVariable
    add_variable!(container, ActivePowerVariable(), devices, C(), tech_model)

    # EnergyBalance
    add_to_expression!(
        container,
        EnergyBalance(),
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
    ::OperationCostModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:NodalBalanceModel},
) where {
    T <: GenericTransportTechnology,
    B <: ContinuousInvestment,
    C <: BasicPowerFlow,
    D <: FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    #Line flows
    add_expression!(container, LineFlow(), devices, C(), tech_model, transport_model)

    # EnergyBalance
    add_to_expression!(
        container,
        EnergyBalance(),
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
    ::FeasibilityModel,
    technology_model::TechnologyModel{T, B, C, D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
) where {
    T <: GenericTransportTechnology,
    B <: ContinuousInvestment,
    C <: OperationsTechnologyFormulation,
    D <: FeasibilityTechnologyFormulation,
}

    #TODO: Port get_available_component functions from PSY
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

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
    T <: GenericTransportTechnology,
    B <: ContinuousInvestment,
    C <: OperationsTechnologyFormulation,
    D <: FeasibilityTechnologyFormulation,
}
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    # Capital Component of objective function
    objective_function!(container, devices, B(), tech_model)
    # Add objective function from container to JuMP model
    update_objective_function!(container)

    # Capacity constraint
    add_constraints!(
        container,
        MaximumCumulativeCapacity(),
        CumulativeCapacity(),
        devices,
        tech_model,
        transport_model,
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
    T <: GenericTransportTechnology,
    B <: ContinuousInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    # Dispatch constraint
    add_constraints!(
        container,
        ActivePowerLimitsConstraint(),
        ActivePowerVariable(),
        devices,
        tech_model,
        transport_model,
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
    transport_model::TransportModel{<:NodalBalanceModel},
) where {
    T <: GenericTransportTechnology,
    B <: ContinuousInvestment,
    C <: BasicPowerFlow,
    D <: FeasibilityTechnologyFormulation,
}
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    # Dispatch constraint
    add_constraints!(
        container,
        PowerFlowLimitsConstraint(),
        devices,
        tech_model,
        transport_model,
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
    T <: GenericTransportTechnology,
    B <: ContinuousInvestment,
    C <: OperationsTechnologyFormulation,
    D <: FeasibilityTechnologyFormulation,
}
    #devices = PSIP.get_technologies(T, p)
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    #tech_model = IS.strip_module_name(typeof(technology_model))
    tech_model = IS.strip_module_name(B)

    return
end
