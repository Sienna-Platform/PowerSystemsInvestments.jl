_is_resource(::PSIP.Technology) = false
_is_resource(::PSIP.ResourceTechnology) = true
_is_demand(::PSIP.Technology) = false
_is_demand(::PSIP.DemandTechnology) = true

"""
Return the available technologies attached to `requirement` that participate on
the generation side — `PSIP.ResourceTechnology` subtypes (`SupplyTechnology`,
`StorageTechnology`, `ColocatedSupplyStorageTechnology`). Generic over any
`PSIP.Requirement` so it is shared by all requirement models.
"""
function _contributing_resources(p::PSIP.Portfolio, requirement::PSIP.Requirement)
    return [
        t for t in PSIP.get_contributing_technologies(p, requirement) if
        _is_resource(t) && PSIP.get_available(t)
    ]
end

"""
Return the available technologies attached to `requirement` that participate on
the demand side — `PSIP.DemandTechnology` subtypes (`DemandRequirement`,
`DemandSideTechnology`). Generic over any `PSIP.Requirement`.
"""
function _contributing_demands(p::PSIP.Portfolio, requirement::PSIP.Requirement)
    return [
        t for t in PSIP.get_contributing_technologies(p, requirement) if
        _is_demand(t) && PSIP.get_available(t)
    ]
end
