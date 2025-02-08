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
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    # BuildCapacity variable
    add_variable!(container, BuildCapacity(), devices, B(), tech_model)

    # CumulativeCapacity
    add_expression!(container, CumulativeCapacity(), devices, B(), tech_model)
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
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    add_variable!(container, FlowActivePowerVariable(), devices, C(), tech_model)

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
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]
    tech_model = IS.strip_module_name(B)

    # TODO: Feasibility Models
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
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
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
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    # Dispatch constraint
    add_constraints!(
        container,
        ActivePowerLimitsConstraint(),
        FlowActivePowerVariable(),
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
    T <: GenericTransportTechnology,
    B <: ContinuousInvestment,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = IS.strip_module_name(B)

    # TODO: Feasibility Models
    return
end
