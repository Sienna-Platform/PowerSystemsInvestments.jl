# A line (NodalACTransportTechnology) of the template
struct LineKey
    type::DataType
    name::String
    formulation::DataType
end

# Limit: `fixed_capacity` plus the cumulative capacity of `expandable_lines`
struct MergedCorridor
    name::String
    arc::Tuple{String, String}
    susceptance::Float64
    fixed_capacity::Float64
    expandable_lines::Vector{LineKey}
    fixed_lines::Vector{Tuple{LineKey, Float64}}
end

struct NewCorridor
    name::String
    arc::Tuple{String, String}
    susceptance::Float64
    line::LineKey
end

struct UnitLine
    name::String
    arc::Tuple{String, String}
    susceptance::Float64
    unit_size::Float64
    unit::Int
    line::LineKey
end

# The PTDF is kept whole; `tol` only drops injection terms from the flows
struct PTDFNetworkData <: AbstractNetworkData
    merged_corridors::Vector{MergedCorridor}
    new_corridors::Vector{NewCorridor}
    unit_lines::Vector{UnitLine}
    ptdf::PTDF
    tol::Float64
    monitored::Set{String}
end

const CorridorLines =
    Dict{Tuple{String, String}, Vector{Tuple{PSIP.NodalACTransportTechnology, LineKey}}}

_names(c::MergedCorridor) =
    [c.name; [l.name for l in c.expandable_lines]; [l.name for (l, _) in c.fixed_lines]]

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
        technology = PSIP.get_technology(D, portfolio, name)
        PSIP.get_available(technology) || continue
        push!(
            get!(corridors, minmax(_arc(technology)...), eltype(valtype(corridors))[]),
            (technology, LineKey(D, name, formulation)),
        )
    end
    return
end

# Other transmission technologies are not in the PTDF
_collect_corridor_lines!(
    ::CorridorLines,
    ::PSIP.Portfolio,
    ::TechnologyModel,
    ::Vector{String},
) = nothing

function _unit_count(
    technology::PSIP.NodalACTransportTechnology,
    existing::Float64,
    ::Type{F},
) where {F}
    unit_size = get_unit_size(BuildCapacity(), technology, F())
    count =
        floor(Int, (PSIP.get_capacity_limits(technology).max - existing) / unit_size + 1e-9)
    return _limit_units(technology, max(count, 0), F)
end

_limit_units(::PSIP.NodalACTransportTechnology, count::Int, ::Type{BinaryInvestment}) =
    min(count, 1)

function _limit_units(
    technology::PSIP.NodalACTransportTechnology,
    count::Int,
    ::Type{IntegerInvestment},
)
    if count > MAX_UNIT_LINES
        error(
            "Line $(PSIP.get_name(technology)) can build $count units, each a separate " *
            "PTDF branch, more than the limit of $(MAX_UNIT_LINES). Lower its capacity " *
            "limit, raise its unit size or use ContinuousInvestment.",
        )
    end
    return count
end

function _check_susceptance_per_mw(corridor_name, technologies)
    per_mw = [_susceptance(t) / PSIP.get_unit_size(t) for t in technologies]
    if length(per_mw) > 1 &&
       maximum(per_mw) > (1 + SUSCEPTANCE_PER_MW_TOLERANCE) * minimum(per_mw)
        @warn "Lines on corridor $corridor_name have different susceptance per MW; the corridor limit overstates what they can carry together" lines =
            PSIP.get_name.(technologies)
    end
    return
end

# New corridors and unit lines are always limited, since their limits decide what is built
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
        corridor_lines = corridors[corridor]
        technologies = first.(corridor_lines)
        lines = last.(corridor_lines)
        existing = [PSIP.get_existing_capacity_mw(portfolio, t) for t in technologies]
        continuous = [_is_continuous(line.formulation) for line in lines]
        expandable = [
            c && PSIP.get_capacity_limits(t).max > mw for
            (t, mw, c) in zip(technologies, existing, continuous)
        ]
        if any(>(0.0), existing)
            corridor_name = join(corridor, "_")
            existing_technologies =
                [t for (t, mw) in zip(technologies, existing) if mw > 0.0]
            _check_susceptance_per_mw(
                corridor_name,
                unique(
                    [
                        existing_technologies
                        [t for (t, c) in zip(technologies, continuous) if c]
                    ],
                ),
            )
            fixed_lines = [
                (line, mw) for
                (line, mw, e) in zip(lines, existing, expandable) if !e && mw > 0.0
            ]
            push!(
                merged_corridors,
                MergedCorridor(
                    corridor_name,
                    corridor,
                    sum(_susceptance, existing_technologies),
                    sum(last, fixed_lines; init=0.0),
                    [line for (line, e) in zip(lines, expandable) if e],
                    fixed_lines,
                ),
            )
        else
            for (technology, line, c) in zip(technologies, lines, continuous)
                c || continue
                push!(
                    new_corridors,
                    NewCorridor(
                        line.name,
                        _arc(technology),
                        _susceptance(technology),
                        line,
                    ),
                )
            end
        end
        for (technology, line, mw, c) in zip(technologies, lines, existing, continuous)
            c && continue
            for unit in 1:_unit_count(technology, mw, line.formulation)
                push!(
                    unit_lines,
                    UnitLine(
                        "$(line.name)_unit_$(unit)",
                        _arc(technology),
                        _susceptance(technology),
                        PSIP.get_unit_size(technology),
                        unit,
                        line,
                    ),
                )
            end
        end
    end

    if isnothing(monitored)
        monitored_corridors = Set(c.name for c in merged_corridors)
    else
        unknown = setdiff(monitored, Iterators.flatten(_names.(merged_corridors)))
        isempty(unknown) || error(
            "Monitored names $unknown are not merged corridors or lines on merged corridors",
        )
        monitored_corridors =
            Set(c.name for c in merged_corridors if any(in(monitored), _names(c)))
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
    return PTDFNetworkData(
        merged_corridors,
        new_corridors,
        unit_lines,
        ptdf,
        tol,
        monitored_corridors,
    )
end

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
