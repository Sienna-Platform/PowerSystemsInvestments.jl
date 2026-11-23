struct PTDF
    data::Matrix{Float64}
    axes::Tuple{Vector{String}, Vector{String}}
    lookup::Tuple{Dict{String, Int}, Dict{String, Int}}
    subnetworks::Dict{String, Vector{String}}
end

Base.getindex(ptdf::PTDF, branch::AbstractString, node::AbstractString) =
    ptdf.data[ptdf.lookup[1][node], ptdf.lookup[2][branch]]

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

function _island_roots(arcs, node_lookup::Dict{String, Int})
    root = collect(1:length(node_lookup))
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
    return [find_root(ix) for ix in eachindex(root)]
end

function PTDF(
    nodes::Vector{String},
    branches::Vector{String},
    arcs::Vector{Tuple{String, String}},
    susceptances::Vector{Float64};
    reference_nodes::AbstractSet{String}=Set{String}(),
    candidate_branches::AbstractSet{String}=Set{String}(),
)
    IS.@assert_op length(arcs) == length(branches)
    IS.@assert_op length(susceptances) == length(branches)
    node_lookup = _make_lookup(nodes)
    A = _incidence_matrix(arcs, node_lookup)
    BA = SparseArrays.sparse(transpose(A)) * LinearAlgebra.Diagonal(susceptances)

    # Islands include candidate branches, which may join islands that each have a reference
    roots = _island_roots(arcs, node_lookup)
    fixed_roots = _island_roots(
        [arc for (arc, b) in zip(arcs, branches) if !(b in candidate_branches)],
        node_lookup,
    )
    islands = Dict{Int, Vector{String}}()
    for (ix, node) in enumerate(nodes)
        push!(get!(islands, roots[ix], String[]), node)
    end
    subnetworks = Dict{String, Vector{String}}()
    for island in values(islands)
        references = filter(in(reference_nodes), island)
        if isempty(references)
            length(island) > 1 &&
                @warn "No reference node in the island with nodes $island, using $(first(island))"
            subnetworks[first(island)] = island
        else
            !allunique(fixed_roots[node_lookup[r]] for r in references) &&
                @warn "The island with nodes $island has reference nodes $references, using $(first(references))"
            subnetworks[first(references)] = island
        end
    end
    valid_ix = setdiff(eachindex(nodes), [node_lookup[r] for r in keys(subnetworks)])
    data = zeros(length(nodes), length(branches))
    if !isempty(valid_ix)
        ABA = (BA * A)[valid_ix, valid_ix]
        data[valid_ix, :] = LinearAlgebra.lu(ABA) \ Matrix(BA[valid_ix, :])
    end
    return PTDF(data, (nodes, branches), (node_lookup, _make_lookup(branches)), subnetworks)
end

# Per unit on a 1 MVA base, from ohms and kV
function _susceptance(line::PSIP.NodalACTransportTechnology)
    x = PSIP.get_reactance(line)
    voltage = PSIP.get_voltage(line)
    (iszero(x) || iszero(voltage)) &&
        error("Line $(PSIP.get_name(line)) has zero reactance or voltage")
    return voltage^2 / x
end
