# Branches of the PTDF network, built from the nodal AC line technologies of the template. Lines
# are grouped into corridors (node pairs):
#   - the existing lines and continuous candidates of a corridor with existing capacity share one
#     branch;
#   - a continuous candidate on a corridor without existing capacity gets its own branch;
#   - each unit a discrete candidate can build is a separate branch.

struct BranchTechnology
    type::DataType
    name::String
    formulation::DataType
end

# Its limit is `fixed_capacity` plus the cumulative capacity of `technologies` (the continuous
# ones that can be expanded); `fixed_capacity` is the existing capacity of the others (discrete
# ones, and continuous ones whose maximum is their existing capacity).
# Susceptance is that of the lines with existing capacity, whatever the candidates build. An
# unmonitored corridor stays in the PTDF but its flow is not limited.
struct MergedCorridor
    name::String
    arc::Tuple{String, String}
    susceptance::Float64
    fixed_capacity::Float64
    technologies::Vector{BranchTechnology}
    monitored::Bool
    # Existing capacity of each technology that cannot be expanded, which make up fixed_capacity
    fixed_technologies::Vector{Tuple{BranchTechnology, Float64}}
end

struct NewCorridor
    name::String
    arc::Tuple{String, String}
    susceptance::Float64
    technology::BranchTechnology
end

struct UnitLine
    name::String
    arc::Tuple{String, String}
    susceptance::Float64
    unit_size::Float64
    unit::Int
    technology::BranchTechnology
end

# PTDF rows follow the order merged corridors, new corridors, unit lines. The PTDF is kept
# whole: `tol` only drops the small injection terms of the flows, so the coefficients that
# cancel the flow of an unbuilt branch are never cut.
struct PTDFNetworkData <: AbstractNetworkData
    merged_corridors::Vector{MergedCorridor}
    new_corridors::Vector{NewCorridor}
    unit_lines::Vector{UnitLine}
    ptdf::PTDF
    tol::Float64
end

const CorridorLines = Dict{
    Tuple{String, String},
    Vector{Tuple{PSIP.NodalACTransportTechnology, BranchTechnology}},
}

_arc(line::PSIP.NodalACTransportTechnology) =
    (PSIP.get_name(PSIP.get_start_node(line)), PSIP.get_name(PSIP.get_end_node(line)))

_is_continuous(::Type{ContinuousInvestment}) = true
_is_continuous(::Type{<:Union{IntegerInvestment, BinaryInvestment}}) = false

function _collect_corridor_lines!(
    corridors::CorridorLines,
    portfolio::PSIP.Portfolio,
    model::TechnologyModel{D},
    names::Vector{String},
) where {D <: PSIP.NodalACTransportTechnology}
    formulation = get_investment_formulation(model)
    for name in names
        line = PSIP.get_technology(D, portfolio, name)
        PSIP.get_available(line) || continue
        push!(
            get!(corridors, minmax(_arc(line)...), eltype(valtype(corridors))[]),
            (line, BranchTechnology(D, name, formulation)),
        )
    end
    return
end

# Other branch technologies are not in the PTDF
_collect_corridor_lines!(
    ::CorridorLines,
    ::PSIP.Portfolio,
    ::TechnologyModel,
    ::Vector{String},
) = nothing

# Units a discrete technology can build within its capacity limit
function _unit_count(
    line::PSIP.NodalACTransportTechnology,
    existing::Float64,
    ::Type{F},
) where {F}
    unit_size = get_unit_size(BuildCapacity(), line, F())
    count = floor(Int, (PSIP.get_capacity_limits(line).max - existing) / unit_size + 1e-9)
    return _limit_units(line, max(count, 0), F)
end

_limit_units(::PSIP.NodalACTransportTechnology, count::Int, ::Type{BinaryInvestment}) =
    min(count, 1)

function _limit_units(
    line::PSIP.NodalACTransportTechnology,
    count::Int,
    ::Type{IntegerInvestment},
)
    if count > MAX_UNIT_LINES
        error(
            "Line $(PSIP.get_name(line)) can build $count units, each a separate PTDF " *
            "branch, more than the limit of $(MAX_UNIT_LINES). Lower its capacity limit, " *
            "raise its unit size or use ContinuousInvestment.",
        )
    end
    return count
end

function _check_susceptance_per_mw(corridor_name, lines)
    per_mw = [_susceptance(line) / PSIP.get_unit_size(line) for line in lines]
    if length(per_mw) > 1 &&
       maximum(per_mw) > (1 + SUSCEPTANCE_PER_MW_TOLERANCE) * minimum(per_mw)
        @warn "Lines on corridor $corridor_name have different susceptance per MW; the corridor limit overstates what they can carry together" lines =
            PSIP.get_name.(lines)
    end
    return
end

# `monitored` lists the merged corridors whose flow is limited, by corridor name or by the name
# of one of their technologies; all of them are monitored when it is `nothing`. New corridors and
# unit lines are always limited, since their limits also decide whether they are built.
function PTDFNetworkData(
    portfolio::PSIP.Portfolio,
    template::InvestmentModelTemplate;
    tol::Float64=0.0,
    monitored::Union{Nothing, Vector{String}}=nothing,
)
    corridors = CorridorLines()
    for (model, names) in get_branch_models(template)
        _collect_corridor_lines!(corridors, portfolio, model, names)
    end

    merged_corridors = MergedCorridor[]
    new_corridors = NewCorridor[]
    unit_lines = UnitLine[]
    for corridor in sort!(collect(keys(corridors)))
        lines = corridors[corridor]
        existing = [PSIP.get_existing_capacity_mw(portfolio, line) for (line, _) in lines]
        continuous = [_is_continuous(technology.formulation) for (_, technology) in lines]
        # Continuous lines that can add capacity; the limit of the others is a constant
        expandable = [
            c && PSIP.get_capacity_limits(line).max > mw for
            ((line, _), mw, c) in zip(lines, existing, continuous)
        ]
        if any(>(0.0), existing)
            corridor_name = join(corridor, "_")
            existing_lines = [line for ((line, _), mw) in zip(lines, existing) if mw > 0.0]
            _check_susceptance_per_mw(
                corridor_name,
                unique(
                    [
                        existing_lines
                        [line for ((line, _), c) in zip(lines, continuous) if c]
                    ],
                ),
            )
            technologies =
                [technology for ((_, technology), e) in zip(lines, expandable) if e]
            fixed_technologies = [
                (technology, mw) for
                ((_, technology), mw, e) in zip(lines, existing, expandable) if
                !e && mw > 0.0
            ]
            push!(
                merged_corridors,
                MergedCorridor(
                    corridor_name,
                    corridor,
                    sum(_susceptance, existing_lines),
                    sum(last, fixed_technologies; init=0.0),
                    technologies,
                    isnothing(monitored) || any(
                        in(monitored),
                        [
                            corridor_name
                            [t.name for t in technologies]
                            [t.name for (t, _) in fixed_technologies]
                        ],
                    ),
                    fixed_technologies,
                ),
            )
        else
            for ((line, technology), c) in zip(lines, continuous)
                c || continue
                push!(
                    new_corridors,
                    NewCorridor(
                        technology.name,
                        _arc(line),
                        _susceptance(line),
                        technology,
                    ),
                )
            end
        end
        for ((line, technology), mw, c) in zip(lines, existing, continuous)
            c && continue
            for unit in 1:_unit_count(line, mw, technology.formulation)
                push!(
                    unit_lines,
                    UnitLine(
                        "$(technology.name)_unit_$(unit)",
                        _arc(line),
                        _susceptance(line),
                        PSIP.get_unit_size(line),
                        unit,
                        technology,
                    ),
                )
            end
        end
    end

    if !isnothing(monitored)
        known = Set([c.name for c in merged_corridors])
        for c in merged_corridors
            union!(known, [t.name for t in c.technologies])
            union!(known, [t.name for (t, _) in c.fixed_technologies])
        end
        unknown = setdiff(monitored, known)
        isempty(unknown) ||
            error("Monitored lines $unknown are not corridors with existing capacity")
    end

    branches = [merged_corridors; new_corridors; unit_lines]
    nodes = sort!(collect(PSIP.get_regions(PSIP.Node, portfolio)); by=PSIP.get_name)
    ptdf = PTDF(
        PSIP.get_name.(nodes),
        String[b.name for b in branches],
        Tuple{String, String}[b.arc for b in branches],
        Float64[b.susceptance for b in branches];
        reference_nodes=_reference_nodes(nodes),
    )
    return PTDFNetworkData(merged_corridors, new_corridors, unit_lines, ptdf, tol)
end

# Only the PTDF model needs network data
initialize_network!(::TransportModel, ::InvestmentModelTemplate, ::PSIP.Portfolio) = nothing

function initialize_network!(
    transport_model::TransportModel{NodalPTDFModel},
    template::InvestmentModelTemplate,
    portfolio::PSIP.Portfolio,
)
    transport_model.network_data = PTDFNetworkData(
        portfolio,
        template;
        tol=get(transport_model.attributes, "tol", 0.0),
        monitored=get(transport_model.attributes, "monitored", nothing),
    )
    return
end
