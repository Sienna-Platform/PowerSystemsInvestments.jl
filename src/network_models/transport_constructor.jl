function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::TransportModel{SingleRegionBalanceModel},
)
    add_constraints!(container, SingleRegionBalanceConstraint, p)
    add_constraints!(container, SingleRegionBalanceFeasibilityConstraint, p)
end

function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::TransportModel{MultiRegionBalanceModel},
)
    add_constraints!(container, MultiRegionBalanceConstraint, p)
    add_constraints!(container, MultiRegionBalanceFeasibilityConstraint, p)
end

function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    transport_model::TransportModel{NodalBalanceModel},
)
    add_constraints!(
        container,
        NodalBalanceConstraint,
        p,
        get_use_slacks(transport_model),
    )
end
