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
    T <: PSIP.StorageTechnology,
    B <: InvestmentTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # BuildCapacity variables
    add_variable!(container, BuildEnergyCapacity(), devices, B())
    add_variable!(container, BuildPowerCapacity(), devices, B())

    # CumulativeCapacity expressions
    add_expression!(container, p, CumulativePowerCapacity(), devices, B())
    add_expression!(container, p, CumulativeEnergyCapacity(), devices, B())
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::OperationCostModel,
    tech_type::Type{T},
    tech_formulation::Type{C},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.StorageTechnology,
    C <: OperationsStorageFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #ActivePowerVariables
    add_variable!(container, ActiveInPowerVariable(), devices, C())
    add_variable!(container, ActiveOutPowerVariable(), devices, C())

    # StateOfChargeVariable
    add_variable!(container, StateOfChargeVariable(), devices, C())

    # EnergyBalance
    add_to_expression!(
        container,
        EnergyBalance(),
        ActiveInPowerVariable(),
        devices,
        C(),
        transport_model,
    )
    add_to_expression!(
        container,
        EnergyBalance(),
        ActiveOutPowerVariable(),
        devices,
        C(),
        transport_model,
    )

    # WeightedEnergyGeneration
    add_expression!(container, WeightedEnergyGeneration(), devices, C())

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::FeasibilityModel,
    tech_type::Type{T},
    tech_formulation::Type{D},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.StorageTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # TODO: Decide if we want different variables or not for feasibility

    # EnergyBalance
    add_to_expression!(
        container,
        FeasibilitySurplus(),
        ActiveInPowerVariable(),
        devices,
        D(),
        transport_model,
    )
    add_to_expression!(
        container,
        FeasibilitySurplus(),
        ActiveOutPowerVariable(),
        devices,
        D(),
        transport_model,
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
    T <: PSIP.StorageTechnology,
    B <: InvestmentTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # Capital Component of objective function
    objective_function!(container, devices, B())

    # Add objective function from container to JuMP model
    update_objective_function!(container)

    # Capacity constraints
    add_constraints!(
        container,
        MaximumCumulativePowerCapacity(),
        CumulativePowerCapacity(),
        devices,
        B(),
    )

    add_constraints!(
        container,
        MaximumCumulativeEnergyCapacity(),
        CumulativeEnergyCapacity(),
        devices,
        B(),
    )

    # TODO: Implement Constraints on Ratio Energy vs Power
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
    T <: PSIP.StorageTechnology,
    C <: OperationsStorageFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # Operations Component of objective function
    objective_function!(container, devices, C())

    # Add objective function from container to JuMP model
    update_objective_function!(container)

    # Dispatch input power constraint
    add_constraints!(
        container,
        InputActivePowerVariableLimitsConstraint(),
        ActiveInPowerVariable(),
        devices,
        C(),
        tech_model_vector,
    )

    # Dispatch output power constraint
    add_constraints!(
        container,
        OutputActivePowerVariableLimitsConstraint(),
        ActiveOutPowerVariable(),
        devices,
        C(),
        tech_model_vector,
    )

    # Energy storage constraint
    add_constraints!(
        container,
        StateOfChargeLimitsConstraint(),
        StateOfChargeVariable(),
        devices,
        C(),
        tech_model_vector,
    )

    #State of charge constraint
    add_constraints!(
        container,
        EnergyBalanceConstraint(),
        StateOfChargeVariable(),
        devices,
        C(),
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
    T <: PSIP.StorageTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # TODO: Feasibility models
    return
end
