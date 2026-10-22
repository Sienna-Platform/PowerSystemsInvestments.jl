# DC power flow with the PTDF: one balance per island, and branch flows set by the net injection
# of every node (its EnergyBalance, which under this model holds no line flows). Flow expressions
# are only built for the branches whose flow is limited; the flows of every branch are computed
# after the solve (BranchFlow).
#
# Branches that may not be built (new corridors and the units of discrete lines) are removed with
# virtual transactions: a transaction v[k,t] injected at the start node of branch k and withdrawn at its end node changes
# the flow of every branch c by (PTDF[c,s_k] - PTDF[c,t_k]) * v[k,t]. The actual flow of k is its
# PTDF flow minus v[k,t], so when k is not built (capacity 0) v[k,t] equals its PTDF flow and k has
# no effect on the network. Because every flow includes every transaction, this is exact for any
# set of unbuilt branches (Rahmani et al. 2016, Mehrtash et al. 2020).

# Name, arc and susceptance of the branches that may not be built
_virtual_branches(network::PTDFNetworkData) = [
    [(c.name, c.arc, c.susceptance) for c in network.new_corridors]
    [(l.name, l.arc, l.susceptance) for l in network.unit_lines]
]

_monitored_corridors(network::PTDFNetworkData) =
    [c for c in network.merged_corridors if c.name in network.monitored]

# Monitored merged corridors and every branch that may not be built
_limited_branches(network::PTDFNetworkData) = [
    [c.name for c in _monitored_corridors(network)]
    first.(_virtual_branches(network))
]

# Largest flow limit a branch can reach
_max_flow(corridor::MergedCorridor, portfolio::PSIP.Portfolio) =
    corridor.fixed_capacity + sum(
        PSIP.get_capacity_limits(PSIP.get_technology(t.type, portfolio, t.name)).max for
        t in corridor.technologies;
        init=0.0,
    )
_max_flow(corridor::NewCorridor, portfolio::PSIP.Portfolio) =
    PSIP.get_capacity_limits(
        PSIP.get_technology(corridor.technology.type, portfolio, corridor.technology.name),
    ).max
_max_flow(line::UnitLine, ::PSIP.Portfolio) = line.unit_size

# Flow variable of each limited branch, bounded by the largest limit it can reach. Its flow is
# set by NetworkFlowConstraint, and FlowRateConstraint limits it.
function add_variable!(
    container::SingleOptimizationContainer,
    ::T,
    portfolio::U,
    network::PTDFNetworkData,
) where {T <: FlowActivePowerVariable, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    branches = [_monitored_corridors(network); network.new_corridors; network.unit_lines]
    variable =
        add_variable_container!(container, T(), U, [b.name for b in branches], time_steps)
    for branch in branches
        _add_flow_variable!(variable, container, branch.name, _max_flow(branch, portfolio))
    end
    return
end

function _add_flow_variable!(
    variable,
    container::SingleOptimizationContainer,
    name,
    max_flow,
)
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    for t in get_time_steps(get_time_mapping(container))
        variable[name, t] = JuMP.@variable(
            jump_model,
            lower_bound = -max_flow,
            upper_bound = max_flow,
            base_name = store_names ? "FlowActivePower_{$(name), $(t)}" : ""
        )
    end
    return
end

# Each flow variable equals its PTDF flow, which is written once; the branch's PTDFBranchFlow is
# then the variable, so its limits only have the variable and the capacities
function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::U,
    network::PTDFNetworkData,
) where {T <: NetworkFlowConstraint, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    branches = _limited_branches(network)
    flow = get_expression(container, PTDFBranchFlow(), U)
    variable = get_variable(container, FlowActivePowerVariable(), U)
    constraint = add_constraints_container!(container, T(), U, branches, time_steps)
    for branch in branches
        _add_network_flow!(constraint, flow, variable, container, branch)
    end
    return
end

function _add_network_flow!(
    constraint,
    flow,
    variable,
    container::SingleOptimizationContainer,
    name,
)
    jump_model = get_jump_model(container)
    for t in get_time_steps(get_time_mapping(container))
        constraint[name, t] =
            JuMP.@constraint(jump_model, variable[name, t] == flow[name, t])
        flow[name, t] = JuMP.AffExpr(0.0, variable[name, t] => 1.0)
    end
    return
end

function add_variable!(
    container::SingleOptimizationContainer,
    ::T,
    ::U,
    network::PTDFNetworkData,
) where {T <: BranchBuiltVariable, U <: PSIP.Portfolio}
    time_steps = get_investment_time_steps(get_time_mapping(container))
    names = first.(_virtual_branches(network))
    variable = add_variable_container!(container, T(), U, names, time_steps)
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    for name in names, t in time_steps
        variable[name, t] = JuMP.@variable(
            jump_model,
            binary = true,
            base_name = store_names ? "BranchBuilt_{$(name), $(t)}" : ""
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
    names = first.(_virtual_branches(network))
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
    branches = _limited_branches(network)
    flow = add_expression_container!(container, T(), U, branches, time_steps)
    for branch in branches
        _add_branch_flow!(flow, container, network, branch)
    end
    return
end

function _add_branch_flow!(
    flow,
    container::SingleOptimizationContainer,
    network::PTDFNetworkData,
    branch,
)
    ptdf = network.ptdf
    nodes = ptdf.axes[1]
    node_lookup = ptdf.lookup[1]
    injections = get_expression(container, EnergyBalance(), PSIP.Portfolio)
    transactions = get_variable(container, VirtualTransactionVariable(), PSIP.Portfolio)
    ix = ptdf.lookup[2][branch]
    factors = [(nodes[n], ptdf.data[n, ix]) for n in eachindex(nodes)]
    filter!(((_, factor),) -> abs(factor) > network.tol, factors)
    # Flow on this branch per unit of each virtual transaction, less the branch's own
    transfers = [
        (
            name,
            ptdf.data[node_lookup[arc[1]], ix] - ptdf.data[node_lookup[arc[2]], ix] -
            (name == branch ? 1.0 : 0.0),
        ) for (name, arc, _) in _virtual_branches(network)
    ]
    filter!(((_, factor),) -> !iszero(factor), transfers)
    for t in get_time_steps(get_time_mapping(container))
        expression = JuMP.AffExpr()
        for (node, factor) in factors
            JuMP.add_to_expression!(expression, factor, injections[node, t])
        end
        for (name, factor) in transfers
            JuMP.add_to_expression!(expression, factor, transactions[name, t])
        end
        flow[branch, t] = expression
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

# The limit of a monitored merged corridor is its fixed capacity plus the cumulative capacity of
# its expandable technologies, that of a new corridor its own cumulative capacity, and that of a
# unit line its unit size once built, all in the investment period of each time step. A corridor
# with nothing to expand has a constant limit, applied by one ranged constraint ("range").
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
    monitored = _monitored_corridors(network)
    constant = [c for c in monitored if isempty(c.technologies)]
    limits = [
        [
            (c.name, c.fixed_capacity, c.technologies) for
            c in monitored if !isempty(c.technologies)
        ]
        [(c.name, 0.0, [c.technology]) for c in network.new_corridors]
    ]
    names = [first.(limits); [line.name for line in network.unit_lines]]
    con_lb = add_constraints_container!(container, T(), U, names, time_steps, meta="lb")
    con_ub = add_constraints_container!(container, T(), U, names, time_steps, meta="ub")
    con_range = add_constraints_container!(
        container,
        T(),
        U,
        [c.name for c in constant],
        time_steps,
        meta="range",
    )
    jump_model = get_jump_model(container)
    for corridor in constant
        _add_constant_limit!(con_range, flow, container, corridor)
    end
    built = get_variable(container, BranchBuiltVariable(), U)
    for line in network.unit_lines, op_ix in get_operational_indexes(time_mapping)
        limit = line.unit_size * built[line.name, inverse_invest_mapping[op_ix]]
        for t in consecutive_slices[op_ix]
            con_ub[line.name, t] = JuMP.@constraint(jump_model, flow[line.name, t] <= limit)
            con_lb[line.name, t] =
                JuMP.@constraint(jump_model, flow[line.name, t] >= -limit)
        end
    end
    for (name, fixed_capacity, technologies) in limits
        _add_capacity_limit!(
            con_lb,
            con_ub,
            flow,
            container,
            name,
            fixed_capacity,
            technologies,
        )
    end
    return
end

function _add_constant_limit!(
    con_range,
    flow,
    container::SingleOptimizationContainer,
    corridor::MergedCorridor,
)
    jump_model = get_jump_model(container)
    limit = corridor.fixed_capacity
    for t in get_time_steps(get_time_mapping(container))
        con_range[corridor.name, t] =
            JuMP.@constraint(jump_model, -limit <= flow[corridor.name, t] <= limit)
    end
    return
end

# Limit of a branch whose capacity can be built, in the investment period of each time step
function _add_capacity_limit!(
    con_lb,
    con_ub,
    flow,
    container::SingleOptimizationContainer,
    name,
    fixed_capacity,
    technologies,
)
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    jump_model = get_jump_model(container)
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
    return
end

# Replaces a container by a copy with rows added for `names`, keeping the entries it has
function _add_rows!(containers::Dict, key, names::Vector{String})
    old = containers[key]
    new = DenseAxisArray{eltype(old)}(undef, [axes(old, 1); names], axes(old, 2))
    new.data[1:size(old.data, 1), :] .= old.data
    containers[key] = new
    return new
end

# Starts monitoring merged corridors in a built model: adds their flows, flow variables and
# limits as the build would have, without rebuilding the rest
function add_monitored_corridors!(
    container::SingleOptimizationContainer,
    transport_model::TransportModel{NodalPTDFModel},
    portfolio::PSIP.Portfolio,
    names::Vector{String},
)
    network = get_network_data(transport_model)
    corridors = [c for c in network.merged_corridors if c.name in names]
    isempty(corridors) && return
    union!(network.monitored, names)
    U = PSIP.Portfolio
    flow = _add_rows!(container.expressions, ExpressionKey(PTDFBranchFlow, U), names)
    for name in names
        _add_branch_flow!(flow, container, network, name)
    end
    if get(transport_model.attributes, "flow_variables", false)
        variable =
            _add_rows!(container.variables, VariableKey(FlowActivePowerVariable, U), names)
        constraint = _add_rows!(
            container.constraints,
            ConstraintKey(NetworkFlowConstraint, U),
            names,
        )
        for corridor in corridors
            _add_flow_variable!(
                variable,
                container,
                corridor.name,
                _max_flow(corridor, portfolio),
            )
            _add_network_flow!(constraint, flow, variable, container, corridor.name)
        end
    end
    constant = [c for c in corridors if isempty(c.technologies)]
    expandable = [c for c in corridors if !isempty(c.technologies)]
    con_range = _add_rows!(
        container.constraints,
        ConstraintKey(FlowRateConstraint, U, "range"),
        [c.name for c in constant],
    )
    for corridor in constant
        _add_constant_limit!(con_range, flow, container, corridor)
    end
    expandable_names = [c.name for c in expandable]
    con_lb = _add_rows!(
        container.constraints,
        ConstraintKey(FlowRateConstraint, U, "lb"),
        expandable_names,
    )
    con_ub = _add_rows!(
        container.constraints,
        ConstraintKey(FlowRateConstraint, U, "ub"),
        expandable_names,
    )
    for corridor in expandable
        _add_capacity_limit!(
            con_lb,
            con_ub,
            flow,
            container,
            corridor.name,
            corridor.fixed_capacity,
            corridor.technologies,
        )
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
    built = get_variable(container, BranchBuiltVariable(), U)
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

# The unit lines built of a discrete technology are as many as the units it has built so far, and
# they are its first ones. Taking the first ones breaks the symmetry between identical units and
# keeps a unit built once it is built.
function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::U,
    network::PTDFNetworkData,
) where {T <: UnitLineBuiltConstraint, U <: PSIP.Portfolio}
    time_steps = get_investment_time_steps(get_time_mapping(container))
    built = get_variable(container, BranchBuiltVariable(), U)
    technologies = unique(l -> l.name, [line.technology for line in network.unit_lines])
    con_units = add_constraints_container!(
        container,
        T(),
        U,
        [technology.name for technology in technologies],
        time_steps,
        meta="units",
    )
    con_order = add_constraints_container!(
        container,
        T(),
        U,
        [line.name for line in network.unit_lines if line.unit > 1],
        time_steps,
        meta="order",
    )
    jump_model = get_jump_model(container)
    for technology in technologies
        lines = [l for l in network.unit_lines if l.technology.name == technology.name]
        build = get_variable(
            container,
            BuildCapacity(),
            technology.type,
            string(technology.formulation),
        )
        for t in time_steps
            con_units[technology.name, t] = JuMP.@constraint(
                jump_model,
                sum(built[line.name, t] for line in lines) ==
                sum(build[technology.name, s] for s in first(time_steps):t)
            )
            for (previous, line) in zip(lines[1:(end - 1)], lines[2:end])
                con_order[line.name, t] = JuMP.@constraint(
                    jump_model,
                    built[previous.name, t] >= built[line.name, t]
                )
            end
        end
    end
    return
end

# Largest virtual transaction of each branch that may not be built. When a branch is not built,
# its transaction equals b_k (theta_s - theta_t) in the network without it. Along any path of
# merged corridors from s to t, |theta_s - theta_t| <= sum of Fmax / b over the path, so the
# shortest such path bounds the transaction. When no merged corridors join its ends, the path
# runs through other branches that may be built, and the sum of Fmax / b over every branch bounds
# any such path. Unmonitored corridors are assumed to stay within their limits.
function _virtual_transaction_bounds(network::PTDFNetworkData, portfolio::PSIP.Portfolio)
    nodes = network.ptdf.axes[1]
    node_lookup = network.ptdf.lookup[1]
    neighbors = [Tuple{Int, Float64}[] for _ in nodes]
    for corridor in network.merged_corridors
        weight = _max_flow(corridor, portfolio) / corridor.susceptance
        from, to = (node_lookup[n] for n in corridor.arc)
        push!(neighbors[from], (to, weight))
        push!(neighbors[to], (from, weight))
    end
    longest_path =
        sum(weight for links in neighbors for (_, weight) in links; init=0.0) / 2 + sum(
            _max_flow(b, portfolio) / b.susceptance for
            b in [network.new_corridors; network.unit_lines];
            init=0.0,
        )
    bounds = Dict{String, Float64}()
    for (name, arc, susceptance) in _virtual_branches(network)
        from, to = (node_lookup[n] for n in arc)
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
        bounds[name] = susceptance * (isinf(distance[to]) ? longest_path : distance[to])
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
    names = first.(_virtual_branches(network))
    built = get_variable(container, BranchBuiltVariable(), U)
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

# Names of the line technologies of the network
function _line_technologies(network::PTDFNetworkData)
    names = String[]
    for corridor in network.merged_corridors
        append!(names, [t.name for t in corridor.technologies])
        append!(names, [t.name for (t, _) in corridor.fixed_technologies])
    end
    append!(names, [c.technology.name for c in network.new_corridors])
    append!(names, [l.technology.name for l in network.unit_lines])
    return sort!(unique(names))
end

function add_aux_variable!(
    container::SingleOptimizationContainer,
    ::T,
    ::U,
    network::PTDFNetworkData,
) where {T <: Union{LineFlow, BranchFlow}, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    names = _flow_names(T(), network)
    container.aux_variables[AuxVarKey(T, U)] =
        DenseAxisArray(fill(NaN, length(names), length(time_steps)), names, time_steps)
    return
end

_flow_names(::LineFlow, network::PTDFNetworkData) = _line_technologies(network)
_flow_names(::BranchFlow, network::PTDFNetworkData) = network.ptdf.axes[2]

# Flows need the network data of the transport model, so they are computed by
# calculate_network_values! once the model is solved
calculate_aux_variable_value!(
    ::SingleOptimizationContainer,
    ::AuxVarKey{<:Union{LineFlow, BranchFlow}, <:PSIP.Portfolio},
    ::PSIP.Portfolio,
) = nothing

# Largest exact flow (BranchFlow) of each merged corridor over the time steps, relative to its
# limit in the step's investment period, and its largest flow above that limit (MW)
function _corridor_loading(container::SingleOptimizationContainer, network::PTDFNetworkData)
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    flow = get_aux_variables(container)[AuxVarKey(BranchFlow, PSIP.Portfolio)]
    capacities = Dict{Tuple{DataType, DataType}, Any}()
    loading = Dict{String, Tuple{Float64, Float64}}()
    for corridor in network.merged_corridors
        corridor_capacities = [
            get!(capacities, (t.type, t.formulation)) do
                jump_value.(_capacity_expression(container, t))
            end for t in corridor.technologies
        ]
        ratio, excess = 0.0, -Inf
        for op_ix in get_operational_indexes(time_mapping)
            period = inverse_invest_mapping[op_ix]
            limit =
                corridor.fixed_capacity + sum(
                    capacity[t.name, period] for
                    (t, capacity) in zip(corridor.technologies, corridor_capacities);
                    init=0.0,
                )
            for t in consecutive_slices[op_ix]
                ratio = max(ratio, abs(flow[corridor.name, t]) / limit)
                excess = max(excess, abs(flow[corridor.name, t]) - limit)
            end
        end
        loading[corridor.name] = (ratio, excess)
    end
    return loading
end

# Values computed from the solution and the transport model's network data
calculate_network_values!(
    ::SingleOptimizationContainer,
    ::TransportModel,
    ::PSIP.Portfolio,
) = nothing

# Branch flows are the full PTDF times the net injections (EnergyBalance), plus the effect of the virtual
# transactions. A merged corridor's flow is shared among its lines in proportion to capacity: each
# continuous technology by its cumulative capacity in the period, and each discrete one by its
# existing capacity (its new units are branches of their own). Line flows are signed from each
# technology's start node to its end node.
function calculate_network_values!(
    container::SingleOptimizationContainer,
    transport_model::TransportModel{NodalPTDFModel},
    portfolio::U,
) where {U <: PSIP.Portfolio}
    network = get_network_data(transport_model)
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    ptdf = network.ptdf
    nodes, branches = ptdf.axes
    node_lookup = ptdf.lookup[1]
    injection = jump_value.(get_expression(container, EnergyBalance(), U))
    transactions = jump_value.(get_variable(container, VirtualTransactionVariable(), U))
    flow = get_aux_variables(container)[AuxVarKey(BranchFlow, U)]
    flow.data .= transpose(ptdf.data) * injection[nodes, :].data
    for (name, arc, _) in _virtual_branches(network)
        transfer = ptdf.data[node_lookup[arc[1]], :] .- ptdf.data[node_lookup[arc[2]], :]
        transfer[ptdf.lookup[2][name]] -= 1.0
        flow.data .+= transfer * transpose(transactions[name, :].data)
    end
    line_flow = get_aux_variables(container)[AuxVarKey(LineFlow, U)]
    fill!(line_flow, 0.0)
    direction(technology, arc) =
        _arc(PSIP.get_technology(technology.type, portfolio, technology.name)) == arc ?
        1.0 : -1.0
    for corridor in network.merged_corridors
        capacities = [
            jump_value.(_capacity_expression(container, technology)) for
            technology in corridor.technologies
        ]
        for op_ix in get_operational_indexes(time_mapping)
            period = inverse_invest_mapping[op_ix]
            shares = [
                [
                    (t, capacity[t.name, period]) for
                    (t, capacity) in zip(corridor.technologies, capacities)
                ]
                corridor.fixed_technologies
            ]
            total = sum(last, shares; init=0.0)
            total > 0.0 || continue
            for (technology, capacity) in shares, t in consecutive_slices[op_ix]
                line_flow[technology.name, t] +=
                    direction(technology, corridor.arc) * capacity / total *
                    flow[corridor.name, t]
            end
        end
    end
    branches = [
        [(c.technology.name, c.name) for c in network.new_corridors]
        [(l.technology.name, l.name) for l in network.unit_lines]
    ]
    for (technology, branch) in branches, t in get_time_steps(time_mapping)
        line_flow[technology, t] += flow[branch, t]
    end
    return
end
