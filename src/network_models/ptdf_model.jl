# A branch that may not be built has a virtual transaction that cancels its flow while it is
# unbuilt (Rahmani et al. 2016, Mehrtash et al. 2020)

_virtual_branches(network::PTDFNetworkData) = [
    [(c.name, c.arc, c.susceptance) for c in network.new_corridors]
    [(l.name, l.arc, l.susceptance) for l in network.unit_lines]
]

_monitored_corridors(network::PTDFNetworkData) =
    [c for c in network.merged_corridors if c.name in network.monitored]

_limited_branches(network::PTDFNetworkData) = [
    [c.name for c in _monitored_corridors(network)]
    first.(_virtual_branches(network))
]

_technology(portfolio::PSIP.Portfolio, line::LineKey) =
    PSIP.get_technology(line.type, portfolio, line.name)

_max_capacity(portfolio::PSIP.Portfolio, line::LineKey) =
    PSIP.get_capacity_limits(_technology(portfolio, line)).max

_max_flow(corridor::MergedCorridor, portfolio::PSIP.Portfolio) =
    corridor.fixed_capacity +
    sum(_max_capacity(portfolio, l) for l in corridor.expandable_lines; init=0.0)
_max_flow(corridor::NewCorridor, portfolio::PSIP.Portfolio) =
    _max_capacity(portfolio, corridor.line)
_max_flow(unit_line::UnitLine, ::PSIP.Portfolio) = unit_line.unit_size

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

# The flow limits then use the variable instead of the PTDF expression
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

    virtual = any(name == branch for (name, _, _) in _virtual_branches(network))
    relative_tol = virtual ? 0.0 : network.relative_tol
    cutoff = max(PTDF_ZERO_TOL, relative_tol * maximum(abs(f) for (_, f) in factors))
    filter!(((_, factor),) -> abs(factor) > cutoff, factors)

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

_capacity_expression(container::SingleOptimizationContainer, line::LineKey) =
    get_expression(container, CumulativeCapacity(), line.type, string(line.formulation))

# |flow| <= limit(investment period)
function _add_flow_limits!(
    con_lb,
    con_ub,
    flow,
    container::SingleOptimizationContainer,
    name,
    limit,
)
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    jump_model = get_jump_model(container)
    for op_ix in get_operational_indexes(time_mapping)
        period_limit = limit(inverse_invest_mapping[op_ix])
        for t in consecutive_slices[op_ix]
            con_ub[name, t] = JuMP.@constraint(jump_model, flow[name, t] <= period_limit)
            con_lb[name, t] = JuMP.@constraint(jump_model, flow[name, t] >= -period_limit)
        end
    end
    return
end

function _capacity_limit(container::SingleOptimizationContainer, fixed_capacity, lines)
    capacities = [_capacity_expression(container, line) for line in lines]
    return period ->
        fixed_capacity + sum(c[l.name, period] for (l, c) in zip(lines, capacities))
end

# A corridor with nothing to expand has a constant limit, set by one ranged constraint
function _add_corridor_limit!(
    con_range,
    con_lb,
    con_ub,
    flow,
    container::SingleOptimizationContainer,
    corridor::MergedCorridor,
)
    if isempty(corridor.expandable_lines)
        limit = corridor.fixed_capacity
        jump_model = get_jump_model(container)
        for t in get_time_steps(get_time_mapping(container))
            con_range[corridor.name, t] =
                JuMP.@constraint(jump_model, -limit <= flow[corridor.name, t] <= limit)
        end
    else
        limit =
            _capacity_limit(container, corridor.fixed_capacity, corridor.expandable_lines)
        _add_flow_limits!(con_lb, con_ub, flow, container, corridor.name, limit)
    end
    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::U,
    network::PTDFNetworkData,
) where {T <: FlowRateConstraint, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    flow = get_expression(container, PTDFBranchFlow(), U)
    monitored = _monitored_corridors(network)
    constant = [c.name for c in monitored if isempty(c.expandable_lines)]
    varying = [
        [c.name for c in monitored if !isempty(c.expandable_lines)]
        first.(_virtual_branches(network))
    ]
    con_range =
        add_constraints_container!(container, T(), U, constant, time_steps, meta="range")
    con_lb = add_constraints_container!(container, T(), U, varying, time_steps, meta="lb")
    con_ub = add_constraints_container!(container, T(), U, varying, time_steps, meta="ub")
    for corridor in monitored
        _add_corridor_limit!(con_range, con_lb, con_ub, flow, container, corridor)
    end
    for c in network.new_corridors
        limit = _capacity_limit(container, 0.0, [c.line])
        _add_flow_limits!(con_lb, con_ub, flow, container, c.name, limit)
    end
    built = get_variable(container, BranchBuiltVariable(), U)
    for u in network.unit_lines
        limit = period -> u.unit_size * built[u.name, period]
        _add_flow_limits!(con_lb, con_ub, flow, container, u.name, limit)
    end
    return
end

function _add_rows!(containers::Dict, key, names::Vector{String})
    old = containers[key]
    new = DenseAxisArray{eltype(old)}(undef, [axes(old, 1); names], axes(old, 2))
    new.data[1:size(old.data, 1), :] .= old.data
    containers[key] = new
    return new
end

# Skips names that are not merged corridors or are already monitored
function add_monitored_corridors!(
    container::SingleOptimizationContainer,
    transport_model::TransportModel{NodalPTDFModel},
    portfolio::PSIP.Portfolio,
    names::Vector{String},
)
    network = get_network_data(transport_model)
    corridors = [
        c for c in network.merged_corridors if
        c.name in names && !(c.name in network.monitored)
    ]
    isempty(corridors) && return
    names = [c.name for c in corridors]
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
    constraints = container.constraints
    constant = [c.name for c in corridors if isempty(c.expandable_lines)]
    expandable = setdiff(names, constant)
    con_range =
        _add_rows!(constraints, ConstraintKey(FlowRateConstraint, U, "range"), constant)
    con_lb = _add_rows!(constraints, ConstraintKey(FlowRateConstraint, U, "lb"), expandable)
    con_ub = _add_rows!(constraints, ConstraintKey(FlowRateConstraint, U, "ub"), expandable)
    for corridor in corridors
        _add_corridor_limit!(con_range, con_lb, con_ub, flow, container, corridor)
    end
    union!(network.monitored, names)
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
        max_capacity = _max_capacity(portfolio, corridor.line)
        capacity = _capacity_expression(container, corridor.line)
        for t in time_steps
            con_capacity[name, t] = JuMP.@constraint(
                jump_model,
                capacity[corridor.line.name, t] <= max_capacity * built[name, t]
            )
            t == first(time_steps) && continue
            con_order[name, t] =
                JuMP.@constraint(jump_model, built[name, t] >= built[name, t - 1])
        end
    end
    return
end

# Units are built in order, which breaks the symmetry between identical units
function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::U,
    network::PTDFNetworkData,
) where {T <: UnitLineBuiltConstraint, U <: PSIP.Portfolio}
    time_steps = get_investment_time_steps(get_time_mapping(container))
    built = get_variable(container, BranchBuiltVariable(), U)
    lines = unique(l -> l.name, [u.line for u in network.unit_lines])
    con_units = add_constraints_container!(
        container,
        T(),
        U,
        [line.name for line in lines],
        time_steps,
        meta="units",
    )
    con_order = add_constraints_container!(
        container,
        T(),
        U,
        [u.name for u in network.unit_lines if u.unit > 1],
        time_steps,
        meta="order",
    )

    jump_model = get_jump_model(container)
    for line in lines
        units = [u for u in network.unit_lines if u.line.name == line.name]
        build =
            get_variable(container, BuildCapacity(), line.type, string(line.formulation))
        for t in time_steps
            con_units[line.name, t] = JuMP.@constraint(
                jump_model,
                sum(built[u.name, t] for u in units) ==
                sum(build[line.name, s] for s in first(time_steps):t)
            )
            for (previous, unit) in zip(units[1:(end - 1)], units[2:end])
                con_order[unit.name, t] = JuMP.@constraint(
                    jump_model,
                    built[previous.name, t] >= built[unit.name, t]
                )
            end
        end
    end
    return
end

# Dijkstra: the distance from `source` to each node and the previous node on its path
function _shortest_paths(neighbors::Vector{Vector{Tuple{Int, Float64}}}, source::Int)
    distance = fill(Inf, length(neighbors))
    previous = zeros(Int, length(neighbors))
    distance[source] = 0.0
    heap = DataStructures.BinaryMinHeap([(0.0, source)])
    while !isempty(heap)
        current_distance, current = pop!(heap)
        current_distance > distance[current] && continue
        for (next, weight) in neighbors[current]
            next_distance = current_distance + weight
            if next_distance < distance[next]
                distance[next] = next_distance
                previous[next] = current
                push!(heap, (next_distance, next))
            end
        end
    end
    return distance, previous
end

# Susceptance times the shortest path of Fmax / b over limited merged corridors between the
# branch's ends, or the sum over all limited branches when only virtual branches join them
function _virtual_transaction_bounds(network::PTDFNetworkData, portfolio::PSIP.Portfolio)
    nodes = network.ptdf.axes[1]
    node_lookup = network.ptdf.lookup[1]
    neighbors = [Tuple{Int, Float64}[] for _ in nodes]
    all_neighbors = [Tuple{Int, Float64}[] for _ in nodes]
    for corridor in network.merged_corridors
        weight = _max_flow(corridor, portfolio) / corridor.susceptance
        from, to = (node_lookup[n] for n in corridor.arc)
        push!(all_neighbors[from], (to, weight))
        push!(all_neighbors[to], (from, weight))
        corridor.name in network.limited || continue
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
    distances = Dict{Int, Vector{Float64}}()
    for (name, arc, susceptance) in _virtual_branches(network)
        from, to = (node_lookup[n] for n in arc)
        distance = get!(() -> first(_shortest_paths(neighbors, from)), distances, from)
        if isinf(distance[to])
            all_distance, previous = _shortest_paths(all_neighbors, from)
            if !isinf(all_distance[to])
                path = String[]
                node = to
                while node != from
                    push!(path, join(minmax(nodes[previous[node]], nodes[node]), "_"))
                    node = previous[node]
                end
                throw(
                    IS.ConflictingInputsError(
                        "The ends of $name are only joined by corridors without flow " *
                        "limits, so its virtual transaction has no valid bound; monitor the " *
                        "corridors $(reverse!(path)) or solve with IterativeMonitoring",
                    ),
                )
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

_flow_names(::LineFlow, network::PTDFNetworkData) = sort!(
    unique(
        [
            [n for c in network.merged_corridors for n in _names(c)[2:end]]
            [c.line.name for c in network.new_corridors]
            [u.line.name for u in network.unit_lines]
        ],
    ),
)
_flow_names(::BranchFlow, network::PTDFNetworkData) = network.ptdf.axes[2]

# Computed by calculate_network_values!
calculate_aux_variable_value!(
    ::SingleOptimizationContainer,
    ::AuxVarKey{<:Union{LineFlow, BranchFlow}, <:PSIP.Portfolio},
    ::PSIP.Portfolio,
) = nothing

function _capacity_values(container::SingleOptimizationContainer, network::PTDFNetworkData)
    values = Dict{Tuple{DataType, DataType}, DenseAxisArray{Float64}}()

    for corridor in network.merged_corridors, line in corridor.expandable_lines
        get!(values, (line.type, line.formulation)) do
            jump_value.(_capacity_expression(container, line))
        end
    end
    return values
end

_capacity_value(values, line::LineKey, period) =
    values[(line.type, line.formulation)][line.name, period]

# Largest exact loading (flow over limit) and excess (MW) of each merged corridor
function _corridor_loading(container::SingleOptimizationContainer, network::PTDFNetworkData)
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    flow = get_aux_variables(container)[AuxVarKey(BranchFlow, PSIP.Portfolio)]
    capacities = _capacity_values(container, network)
    loading = Dict{String, Tuple{Float64, Float64}}()

    for corridor in network.merged_corridors
        ratio, excess = 0.0, -Inf
        for op_ix in get_operational_indexes(time_mapping)
            period = inverse_invest_mapping[op_ix]
            limit =
                corridor.fixed_capacity + sum(
                    _capacity_value(capacities, l, period) for
                    l in corridor.expandable_lines;
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

calculate_network_values!(
    ::SingleOptimizationContainer,
    ::TransportModel,
    ::PSIP.Portfolio,
) = nothing

# A merged corridor's flow is split among its lines in proportion to their capacity
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
    nodes = ptdf.axes[1]
    node_lookup = ptdf.lookup[1]
    injection = jump_value.(get_expression(container, EnergyBalance(), U))
    transactions = jump_value.(get_variable(container, VirtualTransactionVariable(), U))
    flow = get_aux_variables(container)[AuxVarKey(BranchFlow, U)]
    # Each transaction moves power from one end of its branch to the other, and removes the
    # branch's own flow
    injected = copy(injection[nodes, :].data)
    for (name, arc, _) in _virtual_branches(network)
        injected[node_lookup[arc[1]], :] .+= transactions[name, :].data
        injected[node_lookup[arc[2]], :] .-= transactions[name, :].data
    end
    flow.data .= transpose(ptdf.data) * injected
    for (name, _, _) in _virtual_branches(network)
        flow.data[ptdf.lookup[2][name], :] .-= transactions[name, :].data
    end

    line_flow = get_aux_variables(container)[AuxVarKey(LineFlow, U)]
    fill!(line_flow, 0.0)
    capacities = _capacity_values(container, network)
    for corridor in network.merged_corridors
        lines = [corridor.expandable_lines; first.(corridor.fixed_lines)]
        directions = [
            _arc(_technology(portfolio, line)) == corridor.arc ? 1.0 : -1.0 for
            line in lines
        ]
        for op_ix in get_operational_indexes(time_mapping)
            period = inverse_invest_mapping[op_ix]
            shares = [
                [_capacity_value(capacities, l, period) for l in corridor.expandable_lines]
                last.(corridor.fixed_lines)
            ]
            total = sum(shares; init=0.0)
            total > 0.0 || continue
            for (line, direction, share) in zip(lines, directions, shares),
                t in consecutive_slices[op_ix]

                line_flow[line.name, t] +=
                    direction * share / total * flow[corridor.name, t]
            end
        end
    end

    branches = [
        [(c.line.name, c.name) for c in network.new_corridors]
        [(l.line.name, l.name) for l in network.unit_lines]
    ]
    for (line, branch) in branches, t in get_time_steps(time_mapping)
        line_flow[line, t] += flow[branch, t]
    end

    return
end
