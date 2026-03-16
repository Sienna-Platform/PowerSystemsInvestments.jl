function construct_technologies!(
    container::OptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::CapitalCostModel,
    tech_type::Type{T},
    tech_formulation::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.AggregateTransportTechnology,
    B <: ContinuousInvestment,
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
    container::OptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::OperationCostModel,
    tech_type::Type{T},
    tech_formulation::Type{C},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {T <: PSIP.AggregateTransportTechnology, C <: BasicDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    add_variable!(container, FlowActivePowerVariable(), devices, C())

    add_to_expression!(container, EnergyBalance(), devices, C(), transport_model)

    return
end

function construct_technologies!(
    container::OptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::FeasibilityModel,
    tech_type::Type{T},
    tech_formulation::Type{D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.AggregateTransportTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # TODO: Feasibility Models
    return
end

function construct_technologies!(
    container::OptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::CapitalCostModel,
    tech_type::Type{T},
    tech_formulation::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.AggregateTransportTechnology,
    B <: ContinuousInvestment,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # Capital Component of objective function
    objective_function!(container, devices, B())
    # Add objective function from container to JuMP model
    update_objective_function!(container)

    # Capacity constraint
    add_constraints!(
        container,
        MaximumCumulativeCapacity(),
        CumulativeCapacity(),
        devices,
        B(),
    )

    return
end

function construct_technologies!(
    container::OptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::OperationCostModel,
    tech_type::Type{T},
    tech_formulation::Type{C},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {T <: PSIP.AggregateTransportTechnology, C <: BasicDispatch, X <: TechnologyModel}
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
    container::OptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::FeasibilityModel,
    tech_type::Type{T},
    tech_formulation::Type{D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.AggregateTransportTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # TODO: Feasibility Models
    return
end
