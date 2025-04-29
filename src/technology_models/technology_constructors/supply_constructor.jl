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
    T <: PSIP.SupplyTechnology,
    B <: Union{ContinuousInvestment, IntegerInvestment},
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    add_variable!(container, BuildCapacity(), devices, B())

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
) where {T <: PSIP.SupplyTechnology, C <: BasicDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    add_variable!(container, ActivePowerVariable(), devices, C())

    # EnergyBalance
    add_to_expression!(container, EnergyBalance(), devices, C(), transport_model)
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
    T <: PSIP.SupplyTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # Feasibility Surplus
    add_to_expression!(container, FeasibilitySurplus(), devices, D(), transport_model)
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
    T <: PSIP.SupplyTechnology,
    B <: InvestmentTechnologyFormulation,
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
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::OperationCostModel,
    tech_type::Type{T},
    tech_formulation::Type{C},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {T <: PSIP.SupplyTechnology, C <: BasicDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # Operations Component of objective function
    objective_function!(container, devices, C())

    # Add objective function from container to JuMP model
    update_objective_function!(container)

    # Dispatch constraint
    add_constraints!(
        container,
        ActivePowerLimitsConstraint(),
        ActivePowerVariable(),
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
    T <: PSIP.SupplyTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # TODO: Feasibility models

    return
end
