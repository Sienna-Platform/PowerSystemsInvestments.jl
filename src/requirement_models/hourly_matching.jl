_supported_requirement_formulations(::Type{<:PSIP.HourlyMatching}) =
    (RequirementHourlyMatching,)

get_default_attributes(::Type{<:PSIP.HourlyMatching}, ::Type{RequirementHourlyMatching}) =
    Dict{String, Any}("slack_penalty" => REQUIREMENT_SLACK_PENALTY)

function _add_matched_output!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    technology::PSIP.SupplyTechnology,
    tech_model::TechnologyModel{D},
    t::Int,
) where {D <: PSIP.SupplyTechnology}
    meta = string(get_operations_formulation(tech_model))
    output = get_variable(container, ActivePowerVariable(), D, meta)
    for name in get_variable_names(technology)
        JuMP.add_to_expression!(expression, output[name, t])
    end
    return
end

_add_matched_output!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    technology::Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology},
    tech_model::TechnologyModel,
    t::Int,
) = _add_net_injection!(expression, container, tech_model, PSIP.get_name(technology), t)

function construct_requirement!(
    ::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::Type{T},
    ::Type{B},
    ::TransportModel{<:AbstractTransportAggregation},
    names_to_model_map::Dict{String, TechnologyModel},
    ::Vector{X},
) where {T <: PSIP.HourlyMatching, B <: RequirementHourlyMatching, X <: RequirementModel}
    for name in names
        req = PSIP.get_requirement(T, p, name)
        _check_contributors(p, req, names_to_model_map; demands=true)
        _warn_ignored_contributors(_contributing_lines(p, req), req, "Lines")
    end
    return
end

function construct_requirement!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ModelConstructStage,
    ::Type{T},
    ::Type{B},
    ::TransportModel{<:AbstractTransportAggregation},
    names_to_model_map::Dict{String, TechnologyModel},
    requirement_model_vector::Vector{X},
) where {T <: PSIP.HourlyMatching, B <: RequirementHourlyMatching, X <: RequirementModel}
    requirements = [PSIP.get_requirement(T, p, n) for n in names]
    add_constraints!(
        container,
        HourlyMatchingConstraint(),
        p,
        requirements,
        B(),
        names_to_model_map,
        requirement_model_vector,
    )
    return
end

# In each operational time step of every period: output of the resources + slack >= demand
function add_constraints!(
    container::SingleOptimizationContainer,
    ::HourlyMatchingConstraint,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    ::RequirementHourlyMatching,
    names_to_model_map::Dict{String, TechnologyModel},
    requirement_model_vector::Vector{X},
) where {T <: PSIP.HourlyMatching, X <: RequirementModel}
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    operational_indexes = get_operational_indexes(time_mapping)
    time_steps = get_operational_time_steps(time_mapping)
    jump_model = get_jump_model(container)
    con = add_constraints_container!(
        container,
        HourlyMatchingConstraint(),
        T,
        PSIP.get_name.(requirements),
        time_steps,
    )
    slacks =
        _add_slack_container!(container, requirements, requirement_model_vector, time_steps)

    for (req, model) in zip(requirements, requirement_model_vector)
        req_name = PSIP.get_name(req)
        resources = _contributing_resources(p, req)
        resource_models = [
            _contributor_model(names_to_model_map, req_name, resource) for
            resource in resources
        ]
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            demand = _requirement_demand(p, req, time_mapping, op_ix)
            slack_cost =
                get_attributes(model)["slack_penalty"] *
                get_time_step_weight(container, op_ix) *
                _period_cost_factor(container, inverse_invest_mapping[op_ix])
            for (ix, t) in enumerate(time_slices)
                output = JuMP.AffExpr(0.0)
                for (resource, tech_model) in zip(resources, resource_models)
                    _add_matched_output!(output, container, resource, tech_model, t)
                end
                if get_use_slacks(model)
                    _add_requirement_slack!(
                        output,
                        container,
                        slacks,
                        slack_cost,
                        req_name,
                        t,
                    )
                end
                con[req_name, t] = JuMP.@constraint(jump_model, output >= demand[ix])
            end
        end
    end
    return
end
