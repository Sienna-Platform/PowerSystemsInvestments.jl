## For Co-located Technologies: Solar + Wind + Storage ##
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
    T <: PSIP.ColocatedSupplyStorageTechnology,
    B <: InvestmentTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # BuildCapacity variables
    add_variable!(container, BuildEnergyCapacity(), devices, B())
    add_variable!(container, BuildPowerCapacity(), devices, B())
    add_variable!(container, BuildWindCapacity(), devices, B())
    add_variable!(container, BuildSolarCapacity(), devices, B())
    add_variable!(container, BuildInverterCapacity(), devices, B())

    # CumulativeCapacity expressions
    add_expression!(
        container,
        p,
        CumulativePowerCapacity(),
        BuildPowerCapacity(),
        devices,
        B(),
    )
    add_expression!(
        container,
        p,
        CumulativeEnergyCapacity(),
        BuildEnergyCapacity(),
        devices,
        B(),
    )
    add_expression!(
        container,
        p,
        CumulativeWindCapacity(),
        BuildWindCapacity(),
        devices,
        B(),
    )
    add_expression!(
        container,
        p,
        CumulativeSolarCapacity(),
        BuildSolarCapacity(),
        devices,
        B(),
    )
    add_expression!(
        container,
        p,
        CumulativeInverterCapacity(),
        BuildInverterCapacity(),
        devices,
        B(),
    )
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
    T <: PSIP.ColocatedSupplyStorageTechnology,
    C <: OperationsColocatedFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    #ActivePowerVariables
    add_variable!(container, ActiveInPowerVariable(), devices, C())
    add_variable!(container, ActiveOutPowerVariable(), devices, C())
    add_variable!(container, ActivePowerChargeVariable(), devices, C())
    add_variable!(container, ActivePowerDischargeVariable(), devices, C())
    add_variable!(container, ActivePowerWindVariable(), devices, C())
    add_variable!(container, ActivePowerSolarVariable(), devices, C())

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
    T <: PSIP.ColocatedSupplyStorageTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # TODO: Decide if we want different variables or not for feasibility
    error("Co-located is not supported for Feasibility yet")
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
    T <: PSIP.ColocatedSupplyStorageTechnology,
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

    add_constraints!(
        container,
        MaximumCumulativeWindCapacity(),
        CumulativePowerCapacity(),
        devices,
        B(),
    )

    add_constraints!(
        container,
        MaximumCumulativeSolarCapacity(),
        CumulativeEnergyCapacity(),
        devices,
        B(),
    )

    add_constraints!(
        container,
        MaximumCumulativeInverterCapacity(),
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
    T <: PSIP.ColocatedSupplyStorageTechnology,
    C <: OperationsColocatedFormulation,
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
        CumulativeInverterCapacity(),
        devices,
        C(),
        tech_model_vector,
    )

    # Dispatch output power constraint
    add_constraints!(
        container,
        OutputActivePowerVariableLimitsConstraint(),
        ActiveOutPowerVariable(),
        CumulativeInverterCapacity(),
        devices,
        C(),
        tech_model_vector,
    )

    ### Storage ###
    # Dispatch discharge power constraint
    add_constraints!(
        container,
        ActivePowerDischargeVariableLimitsConstraint(),
        ActivePowerDischargeVariable(),
        CumulativePowerCapacity(),
        devices,
        C(),
        tech_model_vector,
    )

    # Dispatch charge power constraint
    add_constraints!(
        container,
        ActivePowerChargeVariableLimitsConstraint(),
        ActivePowerChargeVariable(),
        CumulativePowerCapacity(),
        devices,
        C(),
        tech_model_vector,
    )

    # Energy storage constraint
    add_constraints!(
        container,
        StateOfChargeLimitsConstraint(),
        StateOfChargeVariable(),
        CumulativeEnergyCapacity(),
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

    ##### Solar #####
    add_constraints!(
        container,
        ActivePowerSolarVariableLimitsConstraint(),
        ActivePowerSolarVariable(),
        CumulativeSolarCapacity(),
        devices,
        C(),
        tech_model_vector,
    )
    ##### Wind #####
    add_constraints!(
        container,
        ActivePowerWindVariableLimitsConstraint(),
        ActivePowerWindVariable(),
        CumulativeWindCapacity(),
        devices,
        C(),
        tech_model_vector,
    )
    ##### Co-located balance ####
    add_constraints!(container, ColocatedInternalBalanceConstraint(), devices, C())
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
    T <: PSIP.ColocatedSupplyStorageTechnology,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # TODO: Feasibility models
    error("Feasibility models not supported with colocated technologies")
    return
end
