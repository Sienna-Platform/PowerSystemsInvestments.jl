struct LineKey
    type::DataType
    name::String
    formulation::DataType
end

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

struct PTDFNetworkData <: AbstractNetworkData
    merged_corridors::Vector{MergedCorridor}
    new_corridors::Vector{NewCorridor}
    unit_lines::Vector{UnitLine}
    ptdf::PTDF
    relative_tol::Float64
    monitored::Set{String}
    limited::Set{String}
    transport_lines::Set{String}
end

const CorridorLines =
    Dict{Tuple{String, String}, Vector{Tuple{PSIP.NodalACTransportTechnology, LineKey}}}

_line_names(c::MergedCorridor) =
    [[l.name for l in c.expandable_lines]; [l.name for (l, _) in c.fixed_lines]]
_names(c::MergedCorridor) = [c.name; _line_names(c)]

_is_continuous(::Type{ContinuousInvestment}) = true
_is_continuous(::Type{<:Union{IntegerInvestment, BinaryInvestment}}) = false

function _collect_corridor_lines!(
    corridors::CorridorLines,
    transport_lines::Set{String},
    portfolio::PSIP.Portfolio,
    model::TechnologyModel{D},
    names::Vector{String},
    min_voltage::Float64,
) where {D <: PSIP.NodalACTransportTechnology}
    formulation = get_investment_formulation(model)
    for name in names
        technology = PSIP.get_technology(D, portfolio, name)
        PSIP.get_available(technology) || continue
        if PSIP.get_voltage(technology) < min_voltage
            push!(transport_lines, name)
            continue
        end
        push!(
            get!(corridors, minmax(_arc(technology)...), eltype(valtype(corridors))[]),
            (technology, LineKey(D, name, formulation)),
        )
    end
    return
end

_collect_corridor_lines!(
    ::CorridorLines,
    ::Set{String},
    ::PSIP.Portfolio,
    ::TechnologyModel,
    ::Vector{String},
    ::Float64,
) = nothing

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

function PTDFNetworkData(
    portfolio::PSIP.Portfolio,
    template::InvestmentModelTemplate;
    relative_tol::Float64=0.0,
    monitored::Union{Nothing, Vector{String}}=nothing,
    min_voltage::Float64=0.0,
    monitor_iteratively::Bool=false,
)
    corridors = CorridorLines()
    transport_lines = Set{String}()
    for (model, names) in get_branch_models(template)
        _collect_corridor_lines!(
            corridors,
            transport_lines,
            portfolio,
            model,
            names,
            min_voltage,
        )
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
            # Per MW of rating: existing capacity, or maximum capacity for a new line
            checked = [
                (t, mw > 0.0 ? mw : PSIP.get_capacity_limits(t).max) for
                (t, mw, c) in zip(technologies, existing, continuous) if mw > 0.0 || c
            ]
            per_mw = [_susceptance(t) / rating for (t, rating) in checked]
            if length(per_mw) > 1 &&
               maximum(per_mw) > (1 + SUSCEPTANCE_PER_MW_TOLERANCE) * minimum(per_mw)
                @warn "Lines on corridor $corridor_name have different susceptance per MW; the corridor limit overstates what they can carry together" lines =
                    PSIP.get_name.(first.(checked))
            end
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
            unit_size = get_unit_size(BuildCapacity(), technology, line.formulation())
            max_units = (PSIP.get_capacity_limits(technology).max - mw) / unit_size
            count = _limit_units(
                technology,
                max(floor(Int, max_units + 1e-9), 0),
                line.formulation,
            )
            for unit in 1:count
                push!(
                    unit_lines,
                    UnitLine(
                        "$(line.name)_unit_$(unit)",
                        _arc(technology),
                        _susceptance(technology),
                        unit_size,
                        unit,
                        line,
                    ),
                )
            end
        end
    end

    all_corridors = Set(c.name for c in merged_corridors)
    if isnothing(monitored)
        monitored_corridors = monitor_iteratively ? Set{String}() : copy(all_corridors)
    else
        below_voltage = intersect(monitored, transport_lines)
        isempty(below_voltage) || error(
            "Monitored lines $below_voltage are below the minimum voltage of " *
            "$(min_voltage) kV and are not in the PTDF",
        )
        unknown = setdiff(monitored, Iterators.flatten(_names.(merged_corridors)))
        isempty(unknown) || error(
            "Monitored names $unknown are not merged corridors or lines on merged corridors",
        )
        monitored_corridors =
            Set(c.name for c in merged_corridors if any(in(monitored), _names(c)))
    end
    branches = [merged_corridors; new_corridors; unit_lines]
    names = [b.name for b in branches]
    allunique(names) || error(
        "PTDF branch names $(unique(filter(n -> count(==(n), names) > 1, names))) are " *
        "repeated. Merged corridors are named by their node names joined by `_`, so node " *
        "names that contain `_` can collide.",
    )
    nodes = sort!(collect(PSIP.get_regions(PSIP.Node, portfolio)); by=PSIP.get_name)
    ptdf = PTDF(
        PSIP.get_name.(nodes),
        String[b.name for b in branches],
        Tuple{String, String}[b.arc for b in branches],
        Float64[b.susceptance for b in branches];
        reference_nodes=Set(
            PSIP.get_name(n) for n in nodes if PSIP.get_bus_type(n) == PSY.ACBusTypes.REF
        ),
        candidate_branches=Set{String}(b.name for b in [new_corridors; unit_lines]),
    )
    return PTDFNetworkData(
        merged_corridors,
        new_corridors,
        unit_lines,
        ptdf,
        relative_tol,
        monitored_corridors,
        monitor_iteratively ? all_corridors : copy(monitored_corridors),
        transport_lines,
    )
end

initialize_network!(::TransportModel, ::InvestmentModelTemplate, ::PSIP.Portfolio, ::Bool) =
    nothing

function initialize_network!(
    transport_model::TransportModel{NodalPTDFModel},
    template::InvestmentModelTemplate,
    portfolio::PSIP.Portfolio,
    monitor_iteratively::Bool,
)
    transport_model.network_data = PTDFNetworkData(
        portfolio,
        template;
        monitored=get(transport_model.attributes, "monitored", nothing),
        relative_tol=Float64(get(transport_model.attributes, "relative_tol", 0.0)),
        min_voltage=Float64(get(transport_model.attributes, "min_voltage", 0.0)),
        monitor_iteratively=monitor_iteratively,
    )
    return
end
