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
    T <: PSIP.DemandSideTechnology,
    B <: Union{ContinuousInvestment, IntegerInvestment, BinaryInvestment},
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
) where {T <: PSIP.DemandSideTechnology, C <: EndUseDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]
    foreach(check_end_use, devices)

    add_variable!(container, ActiveInPowerVariable(), devices, C())

    # EnergyBalance
    add_to_expression!(
        container,
        EnergyBalance(),
        ActiveInPowerVariable(),
        devices,
        C(),
        transport_model,
    )

    # Variable cost and product revenue, for results
    add_expression!(container, VariableOMCost(), devices, C())
    add_expression!(container, ProductRevenue(), devices, C())
    return
end

# Consumption is controllable, so end-use technologies are left out of the feasibility check
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
    T <: PSIP.DemandSideTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
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
    T <: PSIP.DemandSideTechnology,
    B <: InvestmentTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # Capital Component of objective function
    objective_function!(container, devices, B())

    # Capacity constraints
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
) where {T <: PSIP.DemandSideTechnology, C <: EndUseDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # Operations Component of objective function
    objective_function!(container, devices, C())

    # Consumption limits and ramps
    add_constraints!(
        container,
        InputActivePowerVariableLimitsConstraint(),
        ActiveInPowerVariable(),
        devices,
        C(),
        tech_model_vector,
    )
    add_constraints!(
        container,
        RampRateConstraint(),
        ActiveInPowerVariable(),
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
    T <: PSIP.DemandSideTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    return
end
