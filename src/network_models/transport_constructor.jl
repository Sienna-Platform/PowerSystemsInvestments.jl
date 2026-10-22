function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::TransportModel{SingleRegionBalanceModel},
)
    add_constraints!(container, SingleRegionBalanceConstraint, p)
    add_constraints!(container, SingleRegionBalanceFeasibilityConstraint, p)
    return
end

function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::TransportModel{MultiRegionBalanceModel},
)
    add_constraints!(container, MultiRegionBalanceConstraint, p)
    add_constraints!(container, MultiRegionBalanceFeasibilityConstraint, p)
    return
end

function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    transport_model::TransportModel{NodalBalanceModel},
)
    add_constraints!(container, NodalBalanceConstraint, p, get_use_slacks(transport_model))
    return
end

function construct_transport!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    transport_model::TransportModel{NodalPTDFModel},
)
    network = get_network_data(transport_model)
    # Slacks are injections at their node, so they are added before the flows
    if get_use_slacks(transport_model)
        _add_balance_slacks!(container, PSIP.Portfolio, network.ptdf.axes[1])
    end
    add_variable!(container, BranchBuiltVariable(), p, network)
    add_variable!(container, VirtualTransactionVariable(), p, network)
    add_expression!(container, PTDFBranchFlow(), p, network)
    # A flow variable per limited branch, so each PTDF flow is written once instead of in both
    # of its limits
    if get(transport_model.attributes, "flow_variables", false)
        add_variable!(container, FlowActivePowerVariable(), p, network)
        add_constraints!(container, NetworkFlowConstraint, p, network)
    end
    add_constraints!(container, IslandBalanceConstraint, p, network)
    add_constraints!(container, FlowRateConstraint, p, network)
    add_constraints!(container, NewCorridorBuiltConstraint, p, network)
    add_constraints!(container, UnitLineBuiltConstraint, p, network)
    add_constraints!(container, VirtualTransactionLimitConstraint, p, network)
    add_aux_variable!(container, BranchFlow(), p, network)
    add_aux_variable!(container, LineFlow(), p, network)
    return
end
