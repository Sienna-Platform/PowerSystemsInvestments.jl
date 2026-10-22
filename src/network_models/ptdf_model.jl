# A branch that may not be built has a virtual transaction that cancels its flow while it is
# unbuilt (Rahmani et al. 2016, Mehrtash et al. 2020)

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
    filter!(((_, factor),) -> abs(factor) > network.tol, factors)
    # The branch's own transaction also removes its flow
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

# A corridor with nothing to expand has a constant limit, set by one ranged constraint
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
    constant = [c for c in monitored if isempty(c.expandable_lines)]
    limits = [
        [
            (c.name, c.fixed_capacity, c.expandable_lines) for
            c in monitored if !isempty(c.expandable_lines)
        ]
        [(c.name, 0.0, [c.line]) for c in network.new_corridors]
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
    for unit_line in network.unit_lines, op_ix in get_operational_indexes(time_mapping)
        name = unit_line.name
        limit = unit_line.unit_size * built[name, inverse_invest_mapping[op_ix]]
        for t in consecutive_slices[op_ix]
            con_ub[name, t] = JuMP.@constraint(jump_model, flow[name, t] <= limit)
            con_lb[name, t] = JuMP.@constraint(jump_model, flow[name, t] >= -limit)
        end
    end
    for (name, fixed_capacity, lines) in limits
        _add_capacity_limit!(con_lb, con_ub, flow, container, name, fixed_capacity, lines)
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

function _add_capacity_limit!(
    con_lb,
    con_ub,
    flow,
    container::SingleOptimizationContainer,
    name,
    fixed_capacity,
    lines,
)
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    jump_model = get_jump_model(container)
    capacities = [_capacity_expression(container, line) for line in lines]
    for op_ix in get_operational_indexes(time_mapping)
        period = inverse_invest_mapping[op_ix]
        limit = JuMP.AffExpr(fixed_capacity)
        for (line, capacity) in zip(lines, capacities)
            JuMP.add_to_expression!(limit, capacity[line.name, period])
        end
        for t in consecutive_slices[op_ix]
            con_ub[name, t] = JuMP.@constraint(jump_model, flow[name, t] <= limit)
            con_lb[name, t] = JuMP.@constraint(jump_model, flow[name, t] >= -limit)
        end
    end
    return
end

# Copy of a container with rows added for `names`
function _add_rows!(containers::Dict, key, names::Vector{String})
    old = containers[key]
    new = DenseAxisArray{eltype(old)}(undef, [axes(old, 1); names], axes(old, 2))
    new.data[1:size(old.data, 1), :] .= old.data
    containers[key] = new
    return new
end

# Adds the flows and limits of merged corridors to a built model
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
    constant = [c for c in corridors if isempty(c.expandable_lines)]
    expandable = [c for c in corridors if !isempty(c.expandable_lines)]
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
            corridor.expandable_lines,
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

# Big-M of each virtual transaction: its branch's susceptance times a bound on the angle
# difference across it, the shortest path of Fmax / b over merged corridors (or the sum over
# all branches when no merged corridors join its ends)
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

function _line_names(network::PTDFNetworkData)
    names = String[]
    for corridor in network.merged_corridors
        append!(names, [l.name for l in corridor.expandable_lines])
        append!(names, [l.name for (l, _) in corridor.fixed_lines])
    end
    append!(names, [c.line.name for c in network.new_corridors])
    append!(names, [l.line.name for l in network.unit_lines])
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

_flow_names(::LineFlow, network::PTDFNetworkData) = _line_names(network)
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
