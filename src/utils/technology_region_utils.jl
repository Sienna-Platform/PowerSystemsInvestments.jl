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
        return [name * TECHNOLOGY_REGION_DELIMITER * PSIP.get_name(r) for r in regions]
    end
    return [name]
end

function get_variable_names_and_regions(d::PSIP.SupplyTechnology)
    regions = PSIP.get_region(d)
    if isempty(regions)
        error("Technology $(PSIP.get_name(d)) is not assigned to any region.")
    end
    return collect(zip(get_variable_names(d), PSIP.get_name.(regions)))
end

# Existing capacity and the minimum capacity limit are not defined per region
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
    if !iszero(PSIP.get_capacity_limits(d).min)
        error(
            "Technology $name is located in more than one region and has a minimum capacity " *
            "limit. Minimum capacity limits are only supported for technologies located in " *
            "a single region.",
        )
    end
    return
end
