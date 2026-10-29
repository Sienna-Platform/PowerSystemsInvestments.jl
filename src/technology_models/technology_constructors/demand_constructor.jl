function construct_technologies!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    model::CapitalCostModel,
    tech_type::Type{T},
    tech_formulation::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {T <: PSIP.DemandRequirement, B <: StaticLoadInvestment, X <: TechnologyModel}
    # Do Nothing. No Load Investment allowed.
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
) where {T <: PSIP.DemandRequirement, C <: BasicDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    # EnergyBalance
    add_to_expression!(container, EnergyBalance(), devices, C(), transport_model)

    # WeightedEnergyDemand
    add_to_expression!(container, WeightedEnergyDemand(), devices, C(), transport_model)

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
) where {T <: PSIP.DemandRequirement, C <: UnservedDemandDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]

    add_variable!(container, UnservedDemandVariable(), devices, C())

    # EnergyBalance
    add_to_expression!(container, EnergyBalance(), devices, C(), transport_model)
    add_to_expression!(
        container,
        EnergyBalance(),
        UnservedDemandVariable(),
        devices,
        C(),
        transport_model,
    )

    # WeightedEnergyDemand
    add_to_expression!(container, WeightedEnergyDemand(), devices, C(), transport_model)

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
    T <: PSIP.DemandRequirement,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    devices = [PSIP.get_technology(T, p, n) for n in names]
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
) where {T <: PSIP.DemandRequirement, B <: StaticLoadInvestment, X <: TechnologyModel}
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
) where {T <: PSIP.DemandRequirement, C <: BasicDispatch, X <: TechnologyModel}
    # Do nothing for loads
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
) where {T <: PSIP.DemandRequirement, C <: UnservedDemandDispatch, X <: TechnologyModel}
    devices = [PSIP.get_technology(T, p, n) for n in names]
    objective_function!(container, devices, C())
    # A quadratic unserved demand cost makes the model a QP, which some solvers (e.g. HiGHS)
    # do not solve with discrete variables
    quadratic = [
        PSIP.get_name(d) for
        d in devices if _quadratic_term(PSIP.get_unserved_demand_cost(d)) != 0.0
    ]
    if !isempty(quadratic) && any(
        v -> JuMP.is_integer(v) || JuMP.is_binary(v),
        JuMP.all_variables(get_jump_model(container)),
    )
        @warn "Demands $(join(quadratic, ", ")) have a quadratic unserved demand cost and " *
              "the model has discrete variables, so it is a mixed-integer QP. HiGHS does " *
              "not solve those."
    end
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
    T <: PSIP.DemandRequirement,
    D <: FeasibilityTechnologyFormulation,
    X <: TechnologyModel,
}
    # Do nothing for loads
    return
end
