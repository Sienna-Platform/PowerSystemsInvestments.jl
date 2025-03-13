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
    if model.attributes["risk_curve"]

        add_constraints!(container, MultiRegionBalanceFeasibilityConstraint, p)
    end

end
