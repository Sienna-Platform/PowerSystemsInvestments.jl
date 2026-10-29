_supported_requirement_formulations(::Type{<:PSIP.HourlyMatching}) =
    (RequirementHourlyMatching,)

get_default_attributes(::Type{<:PSIP.HourlyMatching}, ::Type{RequirementHourlyMatching}) =
    Dict{String, Any}("slack_penalty" => REQUIREMENT_SLACK_PENALTY)

# Output of a resource matched to the demand at a time step: supply output, and the net
# injection of storage and co-located technologies (their charging counts against them)
function _add_matched_output!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.SupplyTechnology,
    operations_meta::String,
    t::Int,
) where {D <: PSIP.SupplyTechnology}
    output = get_variable(container, ActivePowerVariable(), D, operations_meta)
    for name in get_variable_names(technology)
        JuMP.add_to_expression!(expression, output[name, t])
    end
    return
end

function _add_matched_output!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology},
    operations_meta::String,
    t::Int,
) where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    name = PSIP.get_name(technology)
    injection = get_variable(container, ActiveOutPowerVariable(), D, operations_meta)
    withdrawal = get_variable(container, ActiveInPowerVariable(), D, operations_meta)
    JuMP.add_to_expression!(expression, injection[name, t])
    JuMP.add_to_expression!(expression, -1.0, withdrawal[name, t])
    return
end

function construct_requirement!(
    ::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::Type{T},
    ::Type{B},
    ::TransportModel{<:AbstractTransportAggregation},
    ::Dict{String, TechnologyModel},
    ::Vector{X},
) where {T <: PSIP.HourlyMatching, B <: RequirementHourlyMatching, X <: RequirementModel}
    for name in names
        req = PSIP.get_requirement(T, p, name)
        _check_contributors(p, req; demands=true)
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
    time_steps = [t for op_ix in operational_indexes for t in consecutive_slices[op_ix]]
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    demand_expression = get_expression(container, DemandExpression(), PSIP.Portfolio)

    names = PSIP.get_name.(requirements)
    con = add_constraints_container!(
        container,
        HourlyMatchingConstraint(),
        T,
        names,
        time_steps,
    )
    slack_names = [
        PSIP.get_name(req) for
        (req, model) in zip(requirements, requirement_model_vector) if get_use_slacks(model)
    ]
    slacks = if isempty(slack_names)
        nothing
    else
        add_variable_container!(
            container,
            RequirementSlackVariable(),
            T,
            slack_names,
            time_steps,
        )
    end

    for (req, model) in zip(requirements, requirement_model_vector)
        req_name = PSIP.get_name(req)
        resources = _contributing_resources(p, req)
        demands = _contributing_demands(p, req)
        resource_models = [
            _contributor_model(names_to_model_map, req_name, resource) for
            resource in resources
        ]
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            demand = zeros(length(time_slices))
            # Unserved demand does not need to be matched, and shifted demand is matched
            # where it is served
            adjustment = Dict(t => JuMP.AffExpr(0.0) for t in time_slices)
            for d in demands
                formulation = _demand_formulation(names_to_model_map, d)
                for (ix, t) in enumerate(time_slices)
                    demand[ix] += JuMP.constant(demand_expression[PSIP.get_name(d), t])
                end
                _add_unserved_demand!(
                    t -> adjustment[t],
                    container,
                    d,
                    formulation,
                    time_slices,
                    1.0,
                )
                _add_demand_shift!(
                    t -> adjustment[t],
                    container,
                    d,
                    formulation,
                    time_slices,
                    -1.0,
                )
            end
            slack_cost = if req_name in slack_names
                get_attributes(model)["slack_penalty"] *
                get_time_step_weight(container, op_ix) *
                _period_cost_factor(container, inverse_invest_mapping[op_ix])
            else
                0.0
            end
            for (ix, t) in enumerate(time_slices)
                output = JuMP.AffExpr(0.0)
                for (resource, tech_model) in zip(resources, resource_models)
                    _add_matched_output!(
                        output,
                        container,
                        get_technology_type(tech_model),
                        resource,
                        string(get_operations_formulation(tech_model)),
                        t,
                    )
                end
                if req_name in slack_names
                    slacks[req_name, t] = JuMP.@variable(
                        jump_model,
                        lower_bound = 0.0,
                        base_name =
                            store_names ?
                            "RequirementSlackVariable_{$(req_name), $(t)}" : "",
                    )
                    JuMP.add_to_expression!(output, slacks[req_name, t])
                    add_to_objective_operations_expression!(
                        container,
                        slack_cost * slacks[req_name, t],
                    )
                end
                JuMP.add_to_expression!(output, adjustment[t])
                con[req_name, t] = JuMP.@constraint(jump_model, output >= demand[ix])
            end
        end
    end
    return
end
