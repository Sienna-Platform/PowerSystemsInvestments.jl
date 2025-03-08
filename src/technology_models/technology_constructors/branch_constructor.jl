function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::CapitalCostModel,
    tech_type::Type{T},
    tech_formulation::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{TechnologyModel},
) where {T <: GenericTransportTechnology, B <: ContinuousInvestment}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = string(B)

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
    tech_type::Type{T},
    tech_formulation::Type{C},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{TechnologyModel},
) where {T <: GenericTransportTechnology, C <: BasicDispatch}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = string(C)

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
    tech_type::Type{T},
    tech_formulation::Type{D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{TechnologyModel},
) where {T <: GenericTransportTechnology, D <: FeasibilityTechnologyFormulation}
    devices = [PSIP.get_technology(T, p, n) for n in names]
    tech_model = string(D)

    # TODO: Feasibility Models
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
    tech_model_vector::Vector{TechnologyModel},
) where {T <: GenericTransportTechnology, B <: ContinuousInvestment}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = string(B)

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
    tech_type::Type{T},
    tech_formulation::Type{C},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{TechnologyModel},
) where {T <: GenericTransportTechnology, C <: BasicDispatch}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = string(C)

    # Dispatch constraint
    add_constraints!(
        container,
        ActivePowerLimitsConstraint(),
        FlowActivePowerVariable(),
        devices,
        tech_model,
        tech_model_vector,
    )
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
    tech_model_vector::Vector{TechnologyModel},
) where {T <: GenericTransportTechnology, D <: FeasibilityTechnologyFormulation}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #convert technology model to string for container metadata
    tech_model = string(D)

    # TODO: Feasibility Models
    return
end
