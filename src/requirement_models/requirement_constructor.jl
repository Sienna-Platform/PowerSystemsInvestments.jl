function construct_requirements!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    stage::Union{ArgumentConstructStage, ModelConstructStage},
    requirement_map::Dict{Tuple{DataType, DataType}, Vector{String}},
    names_to_model_map::Dict{String, TechnologyModel},
    transport_model::TransportModel{<:AbstractTransportAggregation},
)
    for ((req_type, req_formulation), names) in requirement_map
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
