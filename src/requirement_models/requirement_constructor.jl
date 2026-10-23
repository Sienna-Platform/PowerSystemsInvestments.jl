function construct_requirements!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    stage::Union{ArgumentConstructStage, ModelConstructStage},
    requirement_map::Dict{Tuple{Type, Type}, Vector{String}},
    requirement_names_to_model_map::Dict{String, RequirementModel},
    names_to_model_map::Dict{String, TechnologyModel},
    transport_model::TransportModel{<:AbstractTransportAggregation},
)
    for ((req_type, req_formulation), names) in requirement_map
        requirement_model_vector =
            names_to_requirement_model_vector(requirement_names_to_model_map, names)
        construct_requirement!(
            container,
            p,
            names,
            stage,
            req_type,
            req_formulation,
            transport_model,
            names_to_model_map,
            requirement_model_vector,
        )
        _add_requirement_duals!(container, stage, req_type, requirement_model_vector)
    end
    return
end

_add_requirement_duals!(
    ::SingleOptimizationContainer,
    ::ArgumentConstructStage,
    ::Type{<:PSIP.Requirement},
    ::Vector{<:RequirementModel},
) = nothing

_add_requirement_duals!(
    container::SingleOptimizationContainer,
    ::ModelConstructStage,
    ::Type{T},
    requirement_model_vector::Vector{<:RequirementModel},
) where {T <: PSIP.Requirement} =
    _add_requirement_duals!(container, T, requirement_model_vector)
