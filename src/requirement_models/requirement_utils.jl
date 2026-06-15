"""
Return the available technologies attached to `requirement` that participate on
the generation side — `PSIP.ResourceTechnology` subtypes (`SupplyTechnology`,
`StorageTechnology`, `ColocatedSupplyStorageTechnology`). Generic over any
`PSIP.Requirement` so it is shared by all requirement models.
"""
function _contributing_resources(p::PSIP.Portfolio, requirement::PSIP.Requirement)
    return [
        t for t in PSIP.get_contributing_technologies(p, requirement) if
        t isa PSIP.ResourceTechnology && PSIP.get_available(t)
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
        t isa PSIP.DemandTechnology && PSIP.get_available(t)
    ]
end
