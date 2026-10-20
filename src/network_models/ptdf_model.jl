# DC power flow with the PTDF: one balance per island, and branch flows set by the injections at
# every node (EnergyBalance, which under this model holds no line flows).
#
# Branches that may not be built (new corridors) are removed with virtual transactions: a
# transaction v[k,t] injected at the start node of branch k and withdrawn at its end node changes
# the flow of every branch c by (PTDF[c,s_k] - PTDF[c,t_k]) * v[k,t]. The actual flow of k is its
# PTDF flow minus v[k,t], so when k is not built (capacity 0) v[k,t] equals its PTDF flow and k has
# no effect on the network. Because every flow includes every transaction, this is exact for any
# set of unbuilt branches (Rahmani et al. 2016, Mehrtash et al. 2020).

function add_variable!(
    container::SingleOptimizationContainer,
    ::T,
    ::U,
    network::PTDFNetworkData,
) where {T <: NewCorridorBuiltVariable, U <: PSIP.Portfolio}
    time_steps = get_investment_time_steps(get_time_mapping(container))
    names = [corridor.name for corridor in network.new_corridors]
    variable = add_variable_container!(container, T(), U, names, time_steps)
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    for name in names, t in time_steps
        variable[name, t] = JuMP.@variable(
            jump_model,
            binary = true,
            base_name = store_names ? "NewCorridorBuilt_{$(name), $(t)}" : ""
        )
    end
    return
end

function add_variable!(
    container::SingleOptimizationContainer,
    ::T,
    ::U,
    network::PTDFNetworkData,
) where {T <: VirtualTransactionVariable, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    names = [corridor.name for corridor in network.new_corridors]
    variable = add_variable_container!(container, T(), U, names, time_steps)
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    for name in names, t in time_steps
        variable[name, t] = JuMP.@variable(
            jump_model,
            base_name = store_names ? "VirtualTransaction_{$(name), $(t)}" : ""
        )
    end
    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    ::T,
    ::U,
    network::PTDFNetworkData,
) where {T <: PTDFBranchFlow, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    ptdf = network.ptdf
    nodes, branches = ptdf.axes
    node_lookup = ptdf.lookup[1]
    injections = get_expression(container, EnergyBalance(), U)
    transactions = get_variable(container, VirtualTransactionVariable(), U)
    flow = add_expression_container!(container, T(), U, branches, time_steps)
    for (ix, branch) in enumerate(branches)
        factors = [(nodes[n], ptdf.data[n, ix]) for n in eachindex(nodes)]
        filter!(((_, factor),) -> abs(factor) > network.tol, factors)
        # Flow on this branch per unit of each virtual transaction, less the branch's own
        transfers = [
            (
                corridor.name,
                ptdf.data[node_lookup[corridor.arc[1]], ix] -
                ptdf.data[node_lookup[corridor.arc[2]], ix] -
                (corridor.name == branch ? 1.0 : 0.0),
            ) for corridor in network.new_corridors
        ]
        filter!(((_, factor),) -> !iszero(factor), transfers)
        for t in time_steps
            expression = JuMP.AffExpr()
            for (node, factor) in factors
                JuMP.add_to_expression!(expression, factor, injections[node, t])
            end
            for (name, factor) in transfers
                JuMP.add_to_expression!(expression, factor, transactions[name, t])
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

_capacity_expression(container::SingleOptimizationContainer, technology::BranchTechnology) =
    get_expression(
        container,
        CumulativeCapacity(),
        technology.type,
        string(technology.formulation),
    )

# The limit of a merged corridor is its fixed capacity plus the cumulative capacity of its
# continuous technologies, and that of a new corridor its own cumulative capacity, both in the
# investment period of each time step
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
    limits = [
        [(c.name, c.fixed_capacity, c.technologies) for c in network.merged_corridors]
        [(c.name, 0.0, [c.technology]) for c in network.new_corridors]
    ]
    names = first.(limits)
    con_lb = add_constraints_container!(container, T(), U, names, time_steps, meta="lb")
    con_ub = add_constraints_container!(container, T(), U, names, time_steps, meta="ub")
    jump_model = get_jump_model(container)
    for (name, fixed_capacity, technologies) in limits
        capacities = [_capacity_expression(container, tech) for tech in technologies]
        for op_ix in get_operational_indexes(time_mapping)
            period = inverse_invest_mapping[op_ix]
            limit = JuMP.AffExpr(fixed_capacity)
            for (technology, capacity) in zip(technologies, capacities)
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

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    portfolio::U,
    network::PTDFNetworkData,
) where {T <: NewCorridorBuiltConstraint, U <: PSIP.Portfolio}
    time_steps = get_investment_time_steps(get_time_mapping(container))
    names = [corridor.name for corridor in network.new_corridors]
    built = get_variable(container, NewCorridorBuiltVariable(), U)
    con_capacity =
        add_constraints_container!(container, T(), U, names, time_steps, meta="capacity")
    con_order = add_constraints_container!(
        container,
        T(),
        U,
        names,
        time_steps[2:end],
        meta="order",
    )
    jump_model = get_jump_model(container)
    for corridor in network.new_corridors
        name = corridor.name
        technology = corridor.technology
        line = PSIP.get_technology(technology.type, portfolio, technology.name)
        max_capacity = PSIP.get_capacity_limits(line).max
        capacity = _capacity_expression(container, technology)
        for t in time_steps
            con_capacity[name, t] = JuMP.@constraint(
                jump_model,
                capacity[technology.name, t] <= max_capacity * built[name, t]
            )
            t == first(time_steps) && continue
            con_order[name, t] =
                JuMP.@constraint(jump_model, built[name, t] >= built[name, t - 1])
        end
    end
    return
end

# Largest virtual transaction of each new corridor. When a corridor is not built, its
# transaction equals b_k (theta_s - theta_t) in the network without it. Along any path of
# merged corridors from s to t, |theta_s - theta_t| <= sum of Fmax / b over the path, so the
# shortest such path bounds the transaction. A corridor whose ends no merged corridors join
# cannot carry a transaction, and any bound will do.
function _virtual_transaction_bounds(network::PTDFNetworkData, portfolio::PSIP.Portfolio)
    nodes = network.ptdf.axes[1]
    node_lookup = network.ptdf.lookup[1]
    neighbors = [Tuple{Int, Float64}[] for _ in nodes]
    for corridor in network.merged_corridors
        max_flow =
            corridor.fixed_capacity + sum(
                PSIP.get_capacity_limits(
                    PSIP.get_technology(technology.type, portfolio, technology.name),
                ).max for technology in corridor.technologies;
                init=0.0,
            )
        weight = max_flow / corridor.susceptance
        from, to = (node_lookup[n] for n in corridor.arc)
        push!(neighbors[from], (to, weight))
        push!(neighbors[to], (from, weight))
    end
    bounds = Dict{String, Float64}()
    for corridor in network.new_corridors
        from, to = (node_lookup[n] for n in corridor.arc)
        distance = fill(Inf, length(nodes))
        distance[from] = 0.0
        visited = falses(length(nodes))
        while true
            remaining = findall(!, visited)
            isempty(remaining) && break
            current = remaining[argmin(distance[remaining])]
            isinf(distance[current]) && break
            visited[current] = true
            for (next, weight) in neighbors[current]
                distance[next] = min(distance[next], distance[current] + weight)
            end
        end
        line = PSIP.get_technology(
            corridor.technology.type,
            portfolio,
            corridor.technology.name,
        )
        bounds[corridor.name] = if isinf(distance[to])
            PSIP.get_capacity_limits(line).max
        else
            corridor.susceptance * distance[to]
        end
    end
    return bounds
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    portfolio::U,
    network::PTDFNetworkData,
) where {T <: VirtualTransactionLimitConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    names = [corridor.name for corridor in network.new_corridors]
    built = get_variable(container, NewCorridorBuiltVariable(), U)
    transactions = get_variable(container, VirtualTransactionVariable(), U)
    con_lb = add_constraints_container!(container, T(), U, names, time_steps, meta="lb")
    con_ub = add_constraints_container!(container, T(), U, names, time_steps, meta="ub")
    jump_model = get_jump_model(container)
    bounds = _virtual_transaction_bounds(network, portfolio)
    for name in names, op_ix in get_operational_indexes(time_mapping)
        period = inverse_invest_mapping[op_ix]
        limit = bounds[name] * (1 - built[name, period])
        for t in consecutive_slices[op_ix]
            con_ub[name, t] = JuMP.@constraint(jump_model, transactions[name, t] <= limit)
            con_lb[name, t] = JuMP.@constraint(jump_model, transactions[name, t] >= -limit)
        end
    end
    return
end
