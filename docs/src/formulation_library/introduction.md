# [Formulation Library](@id formulation_library_intro)

The Formulation Library documents the variables, expressions, constraints, and cost terms
that each formulation adds to an investment model. For how the formulations fit together,
see [Formulations](@ref formulation_axes).

## Nomenclature

  - Lowercase letters are used for variables, e.g., ``p`` for power
  - Uppercase letters are used for parameters, e.g., ``C`` for costs
  - Subscripts are used for indexing, e.g., ``(\cdot)_t`` for indexing at time step ``t``
  - Superscripts are used for descriptions, e.g., ``(\cdot)^\text{en}`` to describe an
    energy variable or parameter

All quantities are in natural units: MW, MWh, and dollars.

## Sets and indices

| Symbol                | Description                                                                               |
|:--------------------- |:----------------------------------------------------------------------------------------- |
| ``i \in \mathcal{I}`` | Investment periods, numbered from 1                                                       |
| ``k \in \mathcal{K}`` | Operational (representative) periods, numbered from 1                                     |
| ``\mathcal{K}_i``     | Operational periods that belong to investment period ``i``                                |
| ``t \in \mathcal{T}`` | Operational time steps, numbered consecutively across all operational periods             |
| ``\mathcal{T}_k``     | Time steps in operational period ``k``                                                    |
| ``i(t)``, ``i(k)``    | Investment period that time step ``t`` or operational period ``k`` belongs to             |
| ``g``                 | A technology                                                                              |
| ``r \in \mathcal{R}`` | Regions: a single region, the zones, or the nodes, depending on the transport formulation |

## Common parameters

| Symbol       | Description                                                                      |
|:------------ |:-------------------------------------------------------------------------------- |
| ``W_k``      | Weight of operational period ``k``, from [`OperationalRepresentativeDays`](@ref) |
| ``\Delta_k`` | Length of the time steps in operational period ``k``, in hours                   |
| ``K^0_g``    | Existing capacity of technology ``g``                                            |
| ``K^\max_g`` | Maximum capacity of technology ``g``                                             |

## Valid technology and formulation combinations

A [`TechnologyModel`](@ref) combines a technology type with an investment, an operations,
and a feasibility formulation. The feasibility formulation is
[`BasicDispatchFeasibility`](@ref) in every case.

| Technology type                       | Investment formulations                                                                 | Operations formulations                                                       |
|:------------------------------------- |:--------------------------------------------------------------------------------------- |:----------------------------------------------------------------------------- |
| `SupplyTechnology{ThermalStandard}`   | [`ContinuousInvestment`](@ref), [`IntegerInvestment`](@ref), [`BinaryInvestment`](@ref) | [`BasicDispatch`](@ref)                                                       |
| `SupplyTechnology{RenewableDispatch}` | [`ContinuousInvestment`](@ref), [`IntegerInvestment`](@ref), [`BinaryInvestment`](@ref) | [`BasicDispatch`](@ref)                                                       |
| `SupplyTechnology{HydroDispatch}`     | [`ContinuousInvestment`](@ref), [`IntegerInvestment`](@ref), [`BinaryInvestment`](@ref) | [`BasicDispatch`](@ref), [`BasicDispatchWithBudget`](@ref)                    |
| `StorageTechnology`                   | [`ContinuousInvestment`](@ref), [`IntegerInvestment`](@ref)                             | [`ChronologicalStorageDispatch`](@ref), [`CyclicalStorageDispatch`](@ref)     |
| `ColocatedSupplyStorageTechnology`    | [`ContinuousInvestment`](@ref)                                                          | [`ChronologicalColocatedDispatch`](@ref), [`CyclicalColocatedDispatch`](@ref) |
| `DemandRequirement`                   | [`StaticLoadInvestment`](@ref)                                                          | [`BasicDispatch`](@ref)                                                       |
| `AggregateTransportTechnology`        | [`ContinuousInvestment`](@ref)                                                          | [`BasicDispatch`](@ref)                                                       |
| `NodalACTransportTechnology`          | [`ContinuousInvestment`](@ref)                                                          | [`BasicDispatch`](@ref)                                                       |

Other combinations are not implemented and fail when the model is built.

Requirements are modeled with a [`RequirementModel`](@ref):

| Requirement type          | Formulation                      |
|:------------------------- |:-------------------------------- |
| `EnergyShareRequirements` | [`RequirementEnergyShare`](@ref) |

## Transport formulations and technologies

The transport formulation of the template determines which regions have an energy balance
and which transport technologies take part in it.

| Transport formulation              | Regions with an energy balance | Transport technologies represented |
|:---------------------------------- |:------------------------------ |:---------------------------------- |
| [`SingleRegionBalanceModel`](@ref) | One, for the whole portfolio   | None                               |
| [`MultiRegionBalanceModel`](@ref)  | Each `Zone`                    | `AggregateTransportTechnology`     |
| [`NodalBalanceModel`](@ref)        | Each `Node`                    | `NodalACTransportTechnology`       |

With a [`MultiRegionBalanceModel`](@ref), each supply, storage, and demand technology must
be assigned to exactly one `Zone`. With a [`NodalBalanceModel`](@ref), each storage and
demand technology must be assigned to exactly one `Node`.

## Reading the formulation pages

Each page lists, for a technology type:

  - **Variables**, with their bounds and the symbol used in the equations
  - **Static Parameters**, with the `Portfolio` data they are read from
  - **Time Series Parameters**, with the name of the time series they are read from
  - **Expressions** that the formulation creates or adds to
  - **Objective** terms
  - **Constraints**, with the name of the constraint type in the container

Variables, expressions, and constraints are stored in the optimization container under a
key that combines their type, the technology type, and the name of the formulation that
created them. See [How a Model is Built](@ref build_process).
