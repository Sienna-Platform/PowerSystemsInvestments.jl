"""
Formulation that enforces an energy-share policy: the total generation of a
policy's eligible resources must meet at least a fixed fraction of the total
demand in the policy's eligible regions over the operational horizon.

Named `RequirementEnergyShare` to distinguish the optimization formulation from
the `PSIP.EnergyShareRequirements` data-model struct.
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
Formulation of a carbon tax: the emissions of a policy's technologies with fuel curves cost
`tax_dollars_per_ton` in every year of its target period.
"""
struct RequirementCarbonTax <: RequirementFormulation end
