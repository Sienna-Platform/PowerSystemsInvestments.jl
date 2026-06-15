get_default_attributes(
    ::Type{<:PSIP.EnergyShareRequirements},
    ::Type{RequirementEnergyShare},
) = Dict{String, Any}()

# Argument stage: build the per-policy WeightedEnergyShareGeneration expression by
# aggregating the (already-populated) WeightedEnergyGeneration of the policy's
# eligible resources. This is exported so users can inspect the aggregated
# weighted generation directly in the results.
function construct_requirement!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::Type{T},
    ::Type{B},
    ::TransportModel{<:AbstractTransportAggregation},
    names_to_model_map::Dict{String, TechnologyModel},
) where {T <: PSIP.EnergyShareRequirements, B <: RequirementEnergyShare}
    requirements = [PSIP.get_requirement(T, p, n) for n in names]
    add_expression!(
        container,
        WeightedEnergyShareGeneration(),
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
) where {T <: PSIP.EnergyShareRequirements, B <: RequirementEnergyShare}
    requirements = [PSIP.get_requirement(T, p, n) for n in names]
    add_constraints!(container, EnergyShareRequirementConstraint(), p, requirements, B())
    return
end

"""
Return the operational representative-slice indices (`op_ix`) that belong to the
investment period containing `target_year`. Raises an error if `target_year`
falls outside every investment period.
"""
function _energy_share_operational_indexes(time_mapping::TimeMapping, target_year::Int)
    investment_stamps = get_investment_time_stamps(time_mapping)
    map_to_op = get_investment_map_to_operational_slices(time_mapping)
    target_ivx = findfirst(
        iv -> Dates.year(iv[1]) <= target_year <= Dates.year(iv[2]),
        investment_stamps,
    )
    if isnothing(target_ivx)
        error(
            "EnergyShareRequirement target_year=$(target_year) is not within any " *
            "investment period defined by the capital model.",
        )
    end
    return map_to_op[target_ivx]
end

"""
Build the `WeightedEnergyShareGeneration` expression: for each policy and each
operational index, the sum of the `WeightedEnergyGeneration` of every eligible
resource. Built over all operational indexes for full results visibility; the
energy-share constraint later consumes only the target period's subset.
"""
function add_expression!(
    container::SingleOptimizationContainer,
    ::WeightedEnergyShareGeneration,
    requirements::Vector{T},
    ::RequirementEnergyShare,
    names_to_model_map::Dict{String, TechnologyModel},
) where {T <: PSIP.EnergyShareRequirements}
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)

    requirement_names = [PSIP.get_name(r) for r in requirements]
    expression = add_expression_container!(
        container,
        WeightedEnergyShareGeneration(),
        T,
        requirement_names,
        operational_indexes,
    )

    for req in requirements
        req_name = PSIP.get_name(req)
        eligible_resources = PSIP.get_eligible_resources(req)
        for op_ix in operational_indexes
            share_expr = JuMP.AffExpr(0.0)
            for resource in eligible_resources
                resource_name = PSIP.get_name(resource)
                if !haskey(names_to_model_map, resource_name)
                    error(
                        "EnergyShareRequirement '$(req_name)' lists eligible resource " *
                        "'$(resource_name)' which has no technology model in the template.",
                    )
                end
                tech_model = names_to_model_map[resource_name]
                D = get_technology_type(tech_model)
                ops_meta = string(get_operations_formulation(tech_model))
                weighted_gen =
                    get_expression(container, WeightedEnergyGeneration(), D, ops_meta)
                _add_to_jump_expression!(
                    share_expr,
                    weighted_gen[resource_name, op_ix],
                    1.0,
                )
            end
            expression[req_name, op_ix] = share_expr
        end
    end
    return
end

"""
For each EnergyShareRequirements policy, add one linear constraint over the
representative slices of the investment period containing `target_year`:

    sum_{op_ix} WeightedEnergyShareGeneration[policy, op_ix]
        >= generation_fraction_requirement
           * sum_{r, op_ix} WeightedEnergyDemand[r, op_ix]

where `op_ix` ranges over the target period's operational slices and `r` over the
policy's eligible regions. Both sides reuse the always-on weighted-energy
expressions, so the share is a true (weighted) energy ratio. Errors if an
eligible region is not present in the `WeightedEnergyDemand` axis (e.g. a zone
name under a nodal model).
"""
function add_constraints!(
    container::SingleOptimizationContainer,
    ::EnergyShareRequirementConstraint,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    ::RequirementEnergyShare,
) where {T <: PSIP.EnergyShareRequirements}
    time_mapping = get_time_mapping(container)
    share_gen = get_expression(container, WeightedEnergyShareGeneration(), T)
    demand = get_expression(container, WeightedEnergyDemand(), PSIP.Portfolio)
    demand_regions = axes(demand, 1)

    requirement_names = [PSIP.get_name(r) for r in requirements]
    con = add_constraints_container!(
        container,
        EnergyShareRequirementConstraint(),
        T,
        requirement_names,
    )

    for req in requirements
        req_name = PSIP.get_name(req)
        fraction = PSIP.get_generation_fraction_requirement(req)
        target_year = PSIP.get_target_year(req)
        op_indexes = _energy_share_operational_indexes(time_mapping, target_year)
        region_names = PSIP.get_name.(PSIP.get_eligible_regions(req))

        for region_name in region_names
            if !(region_name in demand_regions)
                error(
                    "EnergyShareRequirement '$(req_name)' references region " *
                    "'$(region_name)' which is not in the WeightedEnergyDemand axis " *
                    "$(collect(demand_regions)). Ensure demand data is assigned to the " *
                    "regions/nodes used by the network model.",
                )
            end
        end

        lhs = JuMP.@expression(
            get_jump_model(container),
            sum(share_gen[req_name, op_ix] for op_ix in op_indexes)
        )
        rhs = JuMP.@expression(
            get_jump_model(container),
            fraction * sum(demand[r, op_ix] for r in region_names, op_ix in op_indexes)
        )

        con[req_name] = JuMP.@constraint(get_jump_model(container), lhs >= rhs)
    end
    return
end
