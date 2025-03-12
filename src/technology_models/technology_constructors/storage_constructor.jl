function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::CapitalCostModel,
    tech_type::T,
    tech_formulation::B,
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
    add_expression!(container, CumulativePowerCapacity(), devices, B())
    add_expression!(container, CumulativeEnergyCapacity(), devices, B())
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::OperationCostModel,
    tech_type::T,
    tech_formulation::C,
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.StorageTechnology,
    C <: OperationsStorageFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #ActivePowerVariables
    add_variable!(container, ActiveInPowerVariable(), devices, C(), tech_model)
    add_variable!(container, ActiveOutPowerVariable(), devices, C(), tech_model)

    # StateOfChargeVariable
    add_variable!(container, StateOfChargeVariable(), devices, C(), tech_model)

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

    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::FeasibilityModel,
    tech_type::T,
    tech_formulation::D,
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
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::CapitalCostModel,
    tech_type::T,
    tech_formulation::B,
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.StorageTechnology,
    B <: InvestmentTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

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

    # TODO: Implement Constraints on Ratio Energy vs Power
    return
end

function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    model::OperationCostModel,
    tech_type::T,
    tech_formulation::C,
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {
    T <: PSIP.StorageTechnology,
    C <: OperationsStorageFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

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
        StateofChargeLimitsConstraint(),
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
    tech_type::T,
    tech_formulation::D,
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
