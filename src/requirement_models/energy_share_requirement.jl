_supported_requirement_formulations(::Type{<:PSIP.EnergyShareRequirements}) =
    (RequirementEnergyShare,)

get_default_attributes(
    ::Type{<:PSIP.EnergyShareRequirements},
    ::Type{RequirementEnergyShare},
) = Dict{String, Any}("slack_penalty" => REQUIREMENT_SLACK_PENALTY)

# Argument stage: validate the policy's contributing technologies, then build its eligible
# generation (WeightedEnergyShareGeneration) and its demand plus storage losses
# (WeightedEnergyShareDemand), both exported so they can be read from the results.
function construct_requirement!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::Type{T},
    ::Type{B},
    ::TransportModel{<:AbstractTransportAggregation},
    names_to_model_map::Dict{String, TechnologyModel},
    requirement_model_vector::Vector{X},
) where {
    T <: PSIP.EnergyShareRequirements,
    B <: RequirementEnergyShare,
    X <: RequirementModel,
}
    requirements = [PSIP.get_requirement(T, p, n) for n in names]
    _validate_energy_share_contributors!(p, requirements)
    add_expression!(
        container,
        WeightedEnergyShareGeneration(),
        p,
        requirements,
        B(),
        names_to_model_map,
    )
    add_expression!(
        container,
        WeightedEnergyShareDemand(),
        p,
        requirements,
        B(),
        names_to_model_map,
    )
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
) where {
    T <: PSIP.EnergyShareRequirements,
    B <: RequirementEnergyShare,
    X <: RequirementModel,
}
    requirements = [PSIP.get_requirement(T, p, n) for n in names]
    add_constraints!(
        container,
        EnergyShareRequirementConstraint(),
        p,
        requirements,
        B(),
        requirement_model_vector,
    )
    return
end

# Investment period containing the target year of a requirement
function _target_investment_period(time_mapping::TimeMapping, requirement::PSIP.Requirement)
    target_year = PSIP.get_target_year(requirement)
    target_ivx = findfirst(
        iv -> Dates.year(iv[1]) <= target_year <= Dates.year(iv[2]),
        get_investment_time_stamps(time_mapping),
    )
    if isnothing(target_ivx)
        error(
            "Requirement $(PSIP.get_name(requirement)) has target year $target_year, which " *
            "is not within any investment period of the capital model.",
        )
    end
    return target_ivx
end

"""
Validate that each EnergyShareRequirements policy has at least one available
contributing resource (numerator) and one available contributing demand
technology (denominator). The error names exactly which side(s) is missing.
"""
function _validate_energy_share_contributors!(
    p::PSIP.Portfolio,
    requirements::Vector{T},
) where {T <: PSIP.EnergyShareRequirements}
    for req in requirements
        req_name = PSIP.get_name(req)
        has_res = !isempty(_contributing_resources(p, req))
        has_dem = !isempty(_contributing_demands(p, req))
        if !has_res && !has_dem
            error(
                "EnergyShareRequirement '$(req_name)' has no available contributing " *
                "resources and no available contributing demand technologies.",
            )
        elseif !has_res
            error(
                "EnergyShareRequirement '$(req_name)' has available contributing demand " *
                "technologies but no available contributing resources.",
            )
        elseif !has_dem
            error(
                "EnergyShareRequirement '$(req_name)' has available contributing " *
                "resources but no available contributing demand technologies.",
            )
        end
    end
    return
end

"""
Build the `WeightedEnergyShareGeneration` expression: for each policy and each
operational index, the weighted eligible generation of its contributing resources (see
`_add_eligible_generation!`).
"""
function add_expression!(
    container::SingleOptimizationContainer,
    ::WeightedEnergyShareGeneration,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    ::RequirementEnergyShare,
    names_to_model_map::Dict{String, TechnologyModel},
) where {T <: PSIP.EnergyShareRequirements}
    operational_indexes = get_operational_indexes(get_time_mapping(container))
    expression = add_expression_container!(
        container,
        WeightedEnergyShareGeneration(),
        T,
        PSIP.get_name.(requirements),
        operational_indexes,
    )
    for req in requirements
        req_name = PSIP.get_name(req)
        for op_ix in operational_indexes
            share_expr = JuMP.AffExpr(0.0)
            _add_eligible_generation!(
                share_expr,
                container,
                p,
                req,
                names_to_model_map,
                op_ix,
            )
            expression[req_name, op_ix] = share_expr
        end
    end
    return
end

"""
Build the `WeightedEnergyShareDemand` expression: for each policy and each operational
index, the weighted demand of its contributing demand technologies, read from their
`"ops_demand"` time series, plus the losses of its contributing storage.
"""
function add_expression!(
    container::SingleOptimizationContainer,
    ::WeightedEnergyShareDemand,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    ::RequirementEnergyShare,
    names_to_model_map::Dict{String, TechnologyModel},
) where {T <: PSIP.EnergyShareRequirements}
    operational_indexes = get_operational_indexes(get_time_mapping(container))
    expression = add_expression_container!(
        container,
        WeightedEnergyShareDemand(),
        T,
        PSIP.get_name.(requirements),
        operational_indexes,
    )
    for req in requirements
        req_name = PSIP.get_name(req)
        for op_ix in operational_indexes
            demand_expr = JuMP.AffExpr(0.0)
            _add_demand_and_storage_losses!(
                demand_expr,
                container,
                p,
                req,
                names_to_model_map,
                op_ix,
            )
            expression[req_name, op_ix] = demand_expr
        end
    end
    return
end

"""
For each EnergyShareRequirements policy, add one linear constraint over the
representative slices of the investment period containing `target_year`:

    sum_{op_ix} WeightedEnergyShareGeneration[policy, op_ix] + slack[policy]
        >= generation_fraction_requirement
           * sum_{op_ix} WeightedEnergyShareDemand[policy, op_ix]

The slack only exists when the policy's `RequirementModel` uses slacks.
"""
function add_constraints!(
    container::SingleOptimizationContainer,
    ::EnergyShareRequirementConstraint,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    ::RequirementEnergyShare,
    requirement_model_vector::Vector{X},
) where {T <: PSIP.EnergyShareRequirements, X <: RequirementModel}
    time_mapping = get_time_mapping(container)
    jump_model = get_jump_model(container)
    share_gen = get_expression(container, WeightedEnergyShareGeneration(), T)
    share_demand = get_expression(container, WeightedEnergyShareDemand(), T)
    map_to_op = get_investment_map_to_operational_slices(time_mapping)
    _add_requirement_slacks!(container, requirements, requirement_model_vector)
    slacks = if has_container_key(container, RequirementSlackVariable, T)
        get_variable(container, RequirementSlackVariable(), T)
    else
        nothing
    end

    con = add_constraints_container!(
        container,
        EnergyShareRequirementConstraint(),
        T,
        PSIP.get_name.(requirements),
    )
    for req in requirements
        req_name = PSIP.get_name(req)
        op_indexes = map_to_op[_target_investment_period(time_mapping, req)]
        lhs = JuMP.AffExpr(0.0)
        if !isnothing(slacks) && req_name in axes(slacks, 1)
            JuMP.add_to_expression!(lhs, slacks[req_name])
        end
        for op_ix in op_indexes
            JuMP.add_to_expression!(lhs, share_gen[req_name, op_ix])
        end
        rhs =
            PSIP.get_generation_fraction_requirement(req) *
            sum(share_demand[req_name, op_ix] for op_ix in op_indexes)
        con[req_name] = JuMP.@constraint(jump_model, lhs >= rhs)
    end
    return
end
