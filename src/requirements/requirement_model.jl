mutable struct RequirementModel{D <: PSIP.Requirement, B <: RequirementFormulation}
    use_slacks::Bool
    duals::Vector{DataType}
    time_series_names::Dict{Type{<:TimeSeriesParameter}, String}
    attributes::Dict{String, Any}
    contributing_devices_map::Dict{Type{<:PSY.Component}, Vector{<:PSY.Component}}
    subsystem::Union{Nothing, String}
    function RequirementModel(
        ::Type{D},
        ::Type{B};
        use_slacks=false,
        duals=Vector{DataType}(),
        attributes=Dict{String, Any}(),
        contributing_devices_map=Dict{
            Type{<:IS.InfrastructureSystemsComponent},
            Vector{<:IS.InfrastructureSystemsComponent},
        }(),
    ) where {D <: PSIP.Requirement, B <: RequirementFormulation}
        # TODO: validate attributes
        #attributes_for_model = get_default_attributes(D, B)
        #for (k, v) in attributes
        #    attributes_for_model[k] = v
        #end
        attributes_for_model = Dict{String, Any}()
        empty_dic = Dict{
            Type{<:IS.InfrastructureSystemsComponent},
            Vector{<:IS.InfrastructureSystemsComponent},
        }()
        #_check_service_formulation(D)
        #_check_service_formulation(B)
        new{D, B}(
            use_slacks,
            duals,
            attributes_for_model,
            contributing_devices_map,
            empty_dic,
        )
    end
end

function _set_model!(
    dict::Dict,
    names::Vector{String},
    model::RequirementModel{D, B},
) where {D <: PSIP.Requirement, B <: RequirementFormulation}
    #key = Symbol(model)
    key = model
    if haskey(dict, key)
        @warn "Overwriting $(D) existing model"
    end
    dict[key] = names
    return
end
