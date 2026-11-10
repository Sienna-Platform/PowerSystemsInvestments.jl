# Names that index the variables and expressions of a technology
get_variable_names(d::PSIP.Technology) = [PSIP.get_name(d)]

function get_variable_names(devices::Vector{<:PSIP.Technology})
    return reduce(vcat, get_variable_names.(devices))
end

# A supply technology in more than one region has separate variables in each of them, named
# <technology name>__<region name>
function get_variable_names(d::PSIP.SupplyTechnology)
    name = PSIP.get_name(d)
    regions = PSIP.get_region(d)
    if length(regions) > 1
        return [name * TECHNOLOGY_REGION_DELIMITER * PSY.get_name(r) for r in regions]
    end
    return [name]
end

function get_variable_names_and_regions(d::PSIP.SupplyTechnology)
    regions = PSIP.get_region(d)
    if isempty(regions)
        error("Technology $(PSIP.get_name(d)) is not assigned to any region.")
    end
    return collect(zip(get_variable_names(d), PSY.get_name.(regions)))
end

# Existing capacity is not defined per region
function check_multi_region_technology(d::PSIP.SupplyTechnology, init_cap)
    if length(PSIP.get_region(d)) <= 1
        return
    end
    name = PSIP.get_name(d)
    if !iszero(init_cap)
        error(
            "Technology $name is located in more than one region and has existing capacity. " *
            "Technologies with existing capacity must be located in a single region.",
        )
    end
    return
end

# Topologies of type T that hold an available technology or end an available line, sorted by
# name. The base system can hold other topologies (its own buses, for example), which the
# model ignores.
function get_model_topologies(port::PSIP.Portfolio, ::Type{T}) where {T <: PSY.Topology}
    used = Set{T}()
    for d in PSIP.get_technologies(PSIP.get_available, PSIP.Technology, port),
        topology in _topologies(d)

        topology isa T && push!(used, topology)
    end
    return sort!(collect(used); by=PSY.get_name)
end

_topologies(d::PSIP.Technology) = PSIP.get_region(d)
_topologies(d::PSIP.AggregateTransportTechnology) =
    [PSIP.get_start_region(d), PSIP.get_end_region(d)]
_topologies(d::Union{PSIP.NodalACTransportTechnology, PSIP.NodalHVDCTransportTechnology}) =
    [PSIP.get_start_node(d), PSIP.get_end_node(d)]
