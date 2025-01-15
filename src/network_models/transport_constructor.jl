function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    model::TransportModel{SingleRegionBalanceModel},
    #names::Vector{String},
    #::ArgumentConstructStage,
)
    add_constraints!(container, SingleRegionBalanceConstraint, p)
    add_constraints!(container, SingleRegionBalanceFeasibilityConstraint, p)
end

function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    model::TransportModel{MultiRegionBalanceModel},
    #names::Vector{String},
    #::ArgumentConstructStage,
)
    add_constraints!(container, MultiRegionBalanceConstraint, p)
end

function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    model::TransportModel{NodalBalanceModel},
    #names::Vector{String},
    #::ArgumentConstructStage,
)

    add_constraints!(container, NodalBalanceConstraint, p)
    add_constraints!(container, AngleLimitsConstraint, p)
    add_constraints!(container, ReferenceBusConstraint, p)

end
