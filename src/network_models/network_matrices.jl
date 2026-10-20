# DC power flow matrices of the nodal network, computed as in PowerNetworkMatrices so the two
# can be swapped later: the incidence matrix is branches × nodes, and PTDF and LODF store their
# transposes, indexed as ptdf[branch, node] and lodf[monitored, outaged].

struct PTDF
    data::Matrix{Float64}
    axes::Tuple{Vector{String}, Vector{String}}
    lookup::Tuple{Dict{String, Int}, Dict{String, Int}}
    arcs::Vector{Tuple{String, String}}
    # Reference node => nodes of its island
    subnetworks::Dict{String, Vector{String}}
end

struct LODF
    data::Matrix{Float64}
    axes::Tuple{Vector{String}, Vector{String}}
    lookup::Tuple{Dict{String, Int}, Dict{String, Int}}
end

Base.getindex(ptdf::PTDF, branch::AbstractString, node::AbstractString) =
    ptdf.data[ptdf.lookup[1][node], ptdf.lookup[2][branch]]
Base.getindex(lodf::LODF, monitored::AbstractString, outaged::AbstractString) =
    lodf.data[lodf.lookup[1][outaged], lodf.lookup[2][monitored]]

function _make_lookup(names::Vector{String})
    lookup = Dict{String, Int}()
    for (ix, name) in enumerate(names)
        haskey(lookup, name) && error("Repeated name $name in the network matrix axes")
        lookup[name] = ix
    end
    return lookup
end

function _incidence_matrix(
    arcs::Vector{Tuple{String, String}},
    node_lookup::Dict{String, Int},
)
    rows = Int[]
    cols = Int[]
    vals = Int8[]
    for (ix, (from, to)) in enumerate(arcs)
        from == to && error("Branch $ix starts and ends at node $from")
        append!(rows, (ix, ix))
        append!(cols, (node_lookup[from], node_lookup[to]))
        append!(vals, (Int8(1), Int8(-1)))
    end
    return SparseArrays.sparse(rows, cols, vals, length(arcs), length(node_lookup))
end

# Islands are found with union-find over the branches. Each is keyed by one reference node:
# the first of its nodes listed in `reference_nodes`, or else its first node.
function _find_subnetworks(
    nodes::Vector{String},
    arcs::Vector{Tuple{String, String}},
    node_lookup::Dict{String, Int},
    reference_nodes::AbstractSet{String},
)
    root = collect(eachindex(nodes))
    function find_root(ix)
        while root[ix] != ix
            root[ix] = root[root[ix]]
            ix = root[ix]
        end
        return ix
    end
    for (from, to) in arcs
        root[find_root(node_lookup[from])] = find_root(node_lookup[to])
    end
    islands = Dict{Int, Vector{String}}()
    for (ix, node) in enumerate(nodes)
        push!(get!(islands, find_root(ix), String[]), node)
    end
    subnetworks = Dict{String, Vector{String}}()
    for island in values(islands)
        references = filter(in(reference_nodes), island)
        if isempty(references)
            length(island) > 1 &&
                @warn "No reference node in the island with nodes $island, using $(first(island))"
            subnetworks[first(island)] = island
        else
            length(references) > 1 &&
                @warn "The island with nodes $island has reference nodes $references, using $(first(references))"
            subnetworks[first(references)] = island
        end
    end
    return subnetworks
end

function PTDF(
    nodes::Vector{String},
    branches::Vector{String},
    arcs::Vector{Tuple{String, String}},
    susceptances::Vector{Float64};
    reference_nodes::AbstractSet{String}=Set{String}(),
    tol::Float64=0.0,
)
    IS.@assert_op length(arcs) == length(branches)
    IS.@assert_op length(susceptances) == length(branches)
    node_lookup = _make_lookup(nodes)
    A = _incidence_matrix(arcs, node_lookup)
    BA = SparseArrays.sparse(transpose(A)) * LinearAlgebra.Diagonal(susceptances)
    subnetworks = _find_subnetworks(nodes, arcs, node_lookup, reference_nodes)
    # Removing each island's reference node makes the nodal susceptance matrix invertible
    valid_ix = setdiff(eachindex(nodes), [node_lookup[r] for r in keys(subnetworks)])
    data = zeros(length(nodes), length(branches))
    if !isempty(valid_ix)
        ABA = (BA * A)[valid_ix, valid_ix]
        data[valid_ix, :] = LinearAlgebra.lu(ABA) \ Matrix(BA[valid_ix, :])
    end
    # Optional cutoff: entries smaller than `tol` are set to zero
    data[abs.(data) .< tol] .= 0.0
    return PTDF(
        data,
        (nodes, branches),
        (node_lookup, _make_lookup(branches)),
        arcs,
        subnetworks,
    )
end

# Reactance in ohms converted to per unit with the line voltage in kV, on a 1 MVA base (the
# base cancels out of the PTDF)
function _susceptance(line::PSIP.NodalACTransportTechnology)
    x = PSIP.get_reactance(line)
    voltage = PSIP.get_voltage(line)
    (iszero(x) || iszero(voltage)) &&
        error("Line $(PSIP.get_name(line)) has zero reactance or voltage")
    return voltage^2 / x
end

_reference_nodes(nodes) =
    Set(PSIP.get_name(n) for n in nodes if PSIP.get_bus_type(n) == PSY.ACBusTypes.REF)

# Available AC lines of the portfolio
function PTDF(portfolio::PSIP.Portfolio; tol::Float64=0.0)
    nodes = sort!(collect(PSIP.get_regions(PSIP.Node, portfolio)); by=PSIP.get_name)
    lines = sort!(
        collect(
            PSIP.get_technologies(
                PSIP.get_available,
                PSIP.NodalACTransportTechnology,
                portfolio,
            ),
        );
        by=PSIP.get_name,
    )
    arcs = [
        (PSIP.get_name(PSIP.get_start_node(l)), PSIP.get_name(PSIP.get_end_node(l))) for
        l in lines
    ]
    return PTDF(
        PSIP.get_name.(nodes),
        PSIP.get_name.(lines),
        arcs,
        _susceptance.(lines);
        reference_nodes=_reference_nodes(nodes),
        tol=tol,
    )
end

# The row of an outaged branch is A * PTDF scaled by 1 / (1 - its own flow sensitivity), with
# -1 on the diagonal. A branch whose outage splits its island keeps an unscaled row, as in
# PowerNetworkMatrices.
function LODF(ptdf::PTDF)
    branches = ptdf.axes[2]
    data = _incidence_matrix(ptdf.arcs, ptdf.lookup[1]) * ptdf.data
    for k in eachindex(branches)
        denominator = 1.0 - data[k, k]
        if denominator >= LODF_ENTRY_TOLERANCE
            data[k, :] ./= denominator
        end
        data[k, k] = -1.0
    end
    return LODF(data, (branches, branches), (ptdf.lookup[2], ptdf.lookup[2]))
end
