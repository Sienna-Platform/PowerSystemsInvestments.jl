# DC power flow with the PTDF: one balance per island, and branch flows set by the injections at
# every node (EnergyBalance, which under this model holds no line flows)

function add_expression!(
    container::SingleOptimizationContainer,
    ::T,
    ::U,
    network::PTDFNetworkData,
) where {T <: PTDFBranchFlow, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    ptdf = network.ptdf
    nodes, branches = ptdf.axes
    injections = get_expression(container, EnergyBalance(), U)
    flow = add_expression_container!(container, T(), U, branches, time_steps)
    for (ix, branch) in enumerate(branches)
        factors = [(nodes[n], ptdf.data[n, ix]) for n in eachindex(nodes)]
        filter!(((_, factor),) -> !iszero(factor), factors)
        for t in time_steps
            expression = JuMP.AffExpr()
            for (node, factor) in factors
                JuMP.add_to_expression!(expression, factor, injections[node, t])
            end
            flow[branch, t] = expression
        end
    end
    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::U,
    network::PTDFNetworkData,
) where {T <: IslandBalanceConstraint, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    subnetworks = network.ptdf.subnetworks
    references = sort!(collect(keys(subnetworks)))
    injections = get_expression(container, EnergyBalance(), U)
    constraint = add_constraints_container!(container, T(), U, references, time_steps)
    jump_model = get_jump_model(container)
    for t in time_steps, reference in references
        constraint[reference, t] = JuMP.@constraint(
            jump_model,
            sum(injections[n, t] for n in subnetworks[reference]) == 0
        )
    end
    return
end

# The limit of a merged corridor is its fixed capacity plus the cumulative capacity of its
# continuous technologies in the investment period of each time step
function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::U,
    network::PTDFNetworkData,
) where {T <: FlowRateConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    flow = get_expression(container, PTDFBranchFlow(), U)
    names = [corridor.name for corridor in network.merged_corridors]
    con_lb = add_constraints_container!(container, T(), U, names, time_steps, meta="lb")
    con_ub = add_constraints_container!(container, T(), U, names, time_steps, meta="ub")
    jump_model = get_jump_model(container)
    for corridor in network.merged_corridors
        name = corridor.name
        capacities = [
            get_expression(
                container,
                CumulativeCapacity(),
                technology.type,
                string(technology.formulation),
            ) for technology in corridor.technologies
        ]
        for op_ix in get_operational_indexes(time_mapping)
            period = inverse_invest_mapping[op_ix]
            limit = JuMP.AffExpr(corridor.fixed_capacity)
            for (technology, capacity) in zip(corridor.technologies, capacities)
                JuMP.add_to_expression!(limit, capacity[technology.name, period])
            end
            for t in consecutive_slices[op_ix]
                con_ub[name, t] = JuMP.@constraint(jump_model, flow[name, t] <= limit)
                con_lb[name, t] = JuMP.@constraint(jump_model, flow[name, t] >= -limit)
            end
        end
    end
    return
end
