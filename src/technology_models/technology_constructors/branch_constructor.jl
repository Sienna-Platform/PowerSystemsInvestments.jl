function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::CapitalCostModel,
    tech_type::Type{T},
    tech_formulation::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.TransmissionTechnology,
    B <: Union{ContinuousInvestment, IntegerInvestment, BinaryInvestment},
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # BuildCapacity variable
    add_variable!(container, BuildCapacity(), devices, B())

    # CumulativeCapacity
    add_expression!(container, p, CumulativeCapacity(), devices, B())
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
    tech_model_vector::Vector{X},
) where {T <: PSIP.TransmissionTechnology, C <: BasicDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]
    lossy = [PSIP.get_name(d) for d in devices if _has_losses(d)]
    isempty(lossy) ||
        @warn "BasicDispatch ignores line losses, which BasicDispatchWithLosses models" lossy

    add_variable!(container, FlowActivePowerVariable(), devices, C())

    add_to_expression!(container, EnergyBalance(), devices, C(), transport_model)

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
    tech_model_vector::Vector{X},
) where {
    T <: ControllableTransportTechnology,
    C <: BasicDispatchWithLosses,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    add_variable!(container, FlowActivePowerFromToVariable(), devices, C())
    add_variable!(container, FlowActivePowerToFromVariable(), devices, C())

    add_to_expression!(
        container,
        EnergyBalance(),
        devices,
        C(),
        transport_model,
        tech_model_vector,
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
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.TransmissionTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
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
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.TransmissionTechnology,
    B <: InvestmentTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # Capital Component of objective function
    objective_function!(container, devices, B())

    # Capacity constraint
    add_constraints!(
        container,
        CumulativeCapacityLimit(),
        CumulativeCapacity(),
        devices,
        B(),
    )
    add_constraints!(
        container,
        SingleUnitInvestmentConstraint(),
        BuildCapacity(),
        devices,
        B(),
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
    tech_model_vector::Vector{X},
) where {T <: PSIP.TransmissionTechnology, C <: BasicDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # Dispatch constraint
    add_constraints!(
        container,
        ActivePowerLimitsConstraint(),
        FlowActivePowerVariable(),
        devices,
        C(),
        tech_model_vector,
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
    tech_model_vector::Vector{X},
) where {
    T <: ControllableTransportTechnology,
    C <: BasicDispatchWithLosses,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]
    add_constraints!(
        container,
        ActivePowerLimitsConstraint(),
        devices,
        C(),
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
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.TransmissionTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    # TODO: Feasibility Models
    return
end

# Under the PTDF model line flows come from the transport model
function construct_technologies!(
    ::SingleOptimizationContainer,
    ::PSIP.Portfolio,
    ::Vector{String},
    ::ArgumentConstructStage,
    ::OperationCostModel,
    ::Type{T},
    ::Type{C},
    ::TransportModel{NodalPTDFModel},
    ::Vector{X},
) where {T <: PSIP.NodalACTransportTechnology, C <: BasicDispatch, X <: TechnologyModel}
    return
end

function construct_technologies!(
    ::SingleOptimizationContainer,
    ::PSIP.Portfolio,
    ::Vector{String},
    ::ModelConstructStage,
    ::OperationCostModel,
    ::Type{T},
    ::Type{C},
    ::TransportModel{NodalPTDFModel},
    ::Vector{X},
) where {T <: PSIP.NodalACTransportTechnology, C <: BasicDispatch, X <: TechnologyModel}
    return
end
