"""
Establishes the model for a particular requirement (policy) specified by type and
formulation. Mirrors `ServiceModel` in PowerSimulations.jl and `TechnologyModel`
in this package.

# Arguments

  - `::Type{D}`: A `PSIP.Requirement` subtype (e.g. `PSIP.EnergyShareRequirements`)
  - `::Type{B}`: A `RequirementFormulation` subtype (e.g. `RequirementEnergyShare`)

# Example

```julia
requirement = RequirementModel(PSIP.EnergyShareRequirements, RequirementEnergyShare)
```
"""
mutable struct RequirementModel{D <: PSIP.Requirement, B <: RequirementFormulation}
    use_slacks::Bool
    duals::Vector{DataType}
    attributes::Dict{String, Any}
end

get_requirement_type(
    ::RequirementModel{D, B},
) where {D <: PSIP.Requirement, B <: RequirementFormulation} = D

get_requirement_formulation(
    ::RequirementModel{D, B},
) where {D <: PSIP.Requirement, B <: RequirementFormulation} = B

get_use_slacks(m::RequirementModel) = m.use_slacks
get_duals(m::RequirementModel) = m.duals
get_attributes(m::RequirementModel) = m.attributes

"""
Default (empty) attributes for a requirement model. Override per
`(requirement_type, formulation)` pair where needed.
"""
get_default_attributes(
    ::Type{<:PSIP.Requirement},
    ::Type{<:RequirementFormulation},
) = Dict{String, Any}()

function RequirementModel(
    ::Type{D},
    ::Type{B};
    use_slacks=false,
    duals=Vector{DataType}(),
    attributes=Dict{String, Any}(),
) where {D <: PSIP.Requirement, B <: RequirementFormulation}
    attributes_ = get_default_attributes(D, B)
    for (k, v) in attributes
        attributes_[k] = v
    end
    return RequirementModel{D, B}(use_slacks, duals, attributes_)
end

function _set_model!(
    dict::Dict,
    names::Vector{String},
    model::RequirementModel{D, B},
) where {D <: PSIP.Requirement, B <: RequirementFormulation}
    key = model
    if haskey(dict, key)
        @warn "Overwriting $(D) existing requirement model"
    end
    dict[key] = names
    return
end
