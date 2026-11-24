"""
Energy share requirement: in the policy's target period, the generation of its eligible
resources is at least `generation_fraction_requirement` times its demand plus the losses of
its storage.
"""
struct RequirementEnergyShare <: RequirementFormulation end

"""
Carbon cap formulations: the yearly emissions of a policy's technologies with fuel curves,
in its target period, are limited to

  - `RequirementCarbonCapMass`: `max_mtons` million tons;
  - `RequirementCarbonCapDemandRate`: `max_tons_mwh` times its demand plus storage losses;
  - `RequirementCarbonCapGenerationRate`: `max_tons_mwh` times its eligible generation.
"""
abstract type CarbonCapFormulation <: RequirementFormulation end
struct RequirementCarbonCapMass <: CarbonCapFormulation end
struct RequirementCarbonCapDemandRate <: CarbonCapFormulation end
struct RequirementCarbonCapGenerationRate <: CarbonCapFormulation end

"""
Capacity reserve margin as in GenX: in every time step of the policy's target period, the
capacity its technologies can provide must cover its demand times `1 + capacity_reserve_fraction`.
"""
struct RequirementCapacityReserveMargin <: RequirementFormulation end

"""
Capacity requirements as in GenX: in the policy's target period, the capacity of its
resources (supply capacity, storage power capacity, co-located wind and solar capacity) is at
least `min_capacity_mw` (`RequirementMinimumCapacity`) or at most `max_capacity_mw`
(`RequirementMaximumCapacity`).
"""
struct RequirementMinimumCapacity <: RequirementFormulation end
struct RequirementMaximumCapacity <: RequirementFormulation end

"""
Hourly matching as in GenX: in every operational time step of every period, the output of
the policy's resources (net of storage charging) covers the demand of its demand
technologies.
"""
struct RequirementHourlyMatching <: RequirementFormulation end

"""
Formulation of a carbon tax: the emissions of a policy's technologies with fuel curves cost
`tax_dollars_per_ton` in every year of its target period.
"""
struct RequirementCarbonTax <: RequirementFormulation end
