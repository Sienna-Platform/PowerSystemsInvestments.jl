function construct_requirements!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    stage::Union{ArgumentConstructStage, ModelConstructStage},
    requirement_models::Dict,
    names_to_model_map::Dict{String, TechnologyModel},
    transport_model::TransportModel{<:AbstractTransportAggregation},
)
    isempty(requirement_models) && return
    for (model, names) in requirement_models
        isempty(names) && continue
        req_type = get_requirement_type(model)
        req_formulation = get_requirement_formulation(model)
        construct_requirement!(
            container,
            p,
            names,
            stage,
            req_type,
            req_formulation,
            transport_model,
            names_to_model_map,
        )
    end
    return
end
