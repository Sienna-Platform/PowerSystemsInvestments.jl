"""
Formulation that enforces an energy-share policy: the total generation of a
policy's eligible resources must meet at least a fixed fraction of the total
demand in the policy's eligible regions over the operational horizon.

Named `RequirementEnergyShare` to distinguish the optimization formulation from
the `PSIP.EnergyShareRequirements` data-model struct.
"""
struct RequirementEnergyShare <: RequirementFormulation end
