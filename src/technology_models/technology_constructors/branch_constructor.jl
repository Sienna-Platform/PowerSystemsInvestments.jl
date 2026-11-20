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

    add_expression!(container, CapitalCostExpression(), devices, B())
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
    _add_basic_dispatch_arguments!(container, devices, C, transport_model)
    return
end

function _add_basic_dispatch_arguments!(
    container::SingleOptimizationContainer,
    devices::Vector{<:PSIP.TransmissionTechnology},
    ::Type{C},
    transport_model::TransportModel,
) where {C <: BasicDispatch}
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
    devices = [PSIP.get_technology(T, p, n) for n in names]
    add_to_expression!(
        container,
        FeasibilityImportCapacity(),
        devices,
        D(),
        transport_model,
        tech_model_vector,
    )
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
        MaximumCumulativeCapacity(),
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
    return
end

# Under the PTDF model the flows of lines at or above the minimum voltage come from the
# transport model; lines below it are dispatched as transport links
function _transport_lines(
    transport_model::TransportModel{NodalPTDFModel},
    names::Vector{String},
    tech_model_vector::Vector{X},
) where {X <: TechnologyModel}
    keep = [n in get_network_data(transport_model).transport_lines for n in names]
    return names[keep], tech_model_vector[keep]
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::OperationCostModel,
    ::Type{T},
    ::Type{C},
    transport_model::TransportModel{NodalPTDFModel},
    tech_model_vector::Vector{X},
) where {T <: PSIP.NodalACTransportTechnology, C <: BasicDispatch, X <: TechnologyModel}
    line_names, _ = _transport_lines(transport_model, names, tech_model_vector)
    isempty(line_names) && return
    devices = [PSIP.get_technology(T, p, n) for n in line_names]
    _add_basic_dispatch_arguments!(container, devices, C, transport_model)
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    ::OperationCostModel,
    ::Type{T},
    ::Type{C},
    transport_model::TransportModel{NodalPTDFModel},
    tech_model_vector::Vector{X},
) where {T <: PSIP.NodalACTransportTechnology, C <: BasicDispatch, X <: TechnologyModel}
    line_names, line_models = _transport_lines(transport_model, names, tech_model_vector)
    isempty(line_names) && return
    devices = [PSIP.get_technology(T, p, n) for n in line_names]
    add_constraints!(
        container,
        ActivePowerLimitsConstraint(),
        FlowActivePowerVariable(),
        devices,
        C(),
        line_models,
    )
    return
end
