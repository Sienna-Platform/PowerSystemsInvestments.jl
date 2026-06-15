get_default_attributes(
    ::Type{<:PSIP.EnergyShareRequirements},
    ::Type{RequirementEnergyShare},
) = Dict{String, Any}()

# Argument stage: validate the policy's contributing technologies, then build the
# two per-policy weighted-energy expressions it consumes — WeightedEnergyShareGeneration
# (from the eligible resources' WeightedEnergyGeneration) and WeightedEnergyShareDemand
# (from the eligible loads' demand time series). Both are exported so users can
# inspect them directly in the results.
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
    _validate_energy_share_contributors!(p, requirements)
    add_expression!(
        container,
        WeightedEnergyShareGeneration(),
        p,
        requirements,
        B(),
        names_to_model_map,
    )
    add_expression!(container, WeightedEnergyShareDemand(), p, requirements, B())
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
    add_constraints!(
        container,
        EnergyShareRequirementConstraint(),
        p,
        requirements,
        B(),
    )
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
operational index, the sum of the `WeightedEnergyGeneration` of every available
contributing resource. Built over all operational indexes for full results
visibility; the energy-share constraint later consumes only the target period's
subset.
"""
function add_expression!(
    container::SingleOptimizationContainer,
    ::WeightedEnergyShareGeneration,
    p::PSIP.Portfolio,
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
        resources = _contributing_resources(p, req)
        for op_ix in operational_indexes
            share_expr = JuMP.AffExpr(0.0)
            for resource in resources
                resource_name = PSIP.get_name(resource)
                if !haskey(names_to_model_map, resource_name)
                    error(
                        "EnergyShareRequirement '$(req_name)' lists contributing resource " *
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
Build the `WeightedEnergyShareDemand` expression: for each policy and each
operational index, the weighted demand of every available contributing demand
technology, read from its `"ops_demand"` time series. A constant `AffExpr`. Built
over all operational indexes for full results visibility.
"""
function add_expression!(
    container::SingleOptimizationContainer,
    ::WeightedEnergyShareDemand,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    ::RequirementEnergyShare,
) where {T <: PSIP.EnergyShareRequirements}
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    operational_weights = get_operational_weights(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    time_stamps = get_time_stamps(time_mapping)

    requirement_names = [PSIP.get_name(r) for r in requirements]
    expression = add_expression_container!(
        container,
        WeightedEnergyShareDemand(),
        T,
        requirement_names,
        operational_indexes,
    )

    for req in requirements
        req_name = PSIP.get_name(req)
        demands = _contributing_demands(p, req)
        for op_ix in operational_indexes
            weight = operational_weights[op_ix]
            time_slices = consecutive_slices[op_ix]
            demand_expr = JuMP.AffExpr(0.0)
            for d in demands
                time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
                # Load Data is in MW
                ts_data = TimeSeries.values(time_series.data)
                first_tstamp = time_stamps[first(time_slices)]
                first_ts_tstamp = first(TimeSeries.timestamp(time_series.data))
                if first_tstamp != first_ts_tstamp
                    @error(
                        "Initial timestamp of timeseries $(IS.get_name(time_series)) of technology $(PSIP.get_name(d)) does not match with the expected representative day $op_ix"
                    )
                end
                _add_to_jump_expression!(demand_expr, weight * sum(ts_data))
            end
            expression[req_name, op_ix] = demand_expr
        end
    end
    return
end

"""
For each EnergyShareRequirements policy, add one linear constraint over the
representative slices of the investment period containing `target_year`:

    sum_{op_ix} WeightedEnergyShareGeneration[policy, op_ix]
        >= generation_fraction_requirement
           * sum_{op_ix} WeightedEnergyShareDemand[policy, op_ix]

where `op_ix` ranges over the target period's operational slices. Both sides reuse
the per-policy weighted-energy expressions built in the argument stage, so the
share is a true (weighted) energy ratio.
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
    share_demand = get_expression(container, WeightedEnergyShareDemand(), T)

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

        lhs = JuMP.@expression(
            get_jump_model(container),
            sum(share_gen[req_name, op_ix] for op_ix in op_indexes)
        )
        rhs = JuMP.@expression(
            get_jump_model(container),
            fraction * sum(share_demand[req_name, op_ix] for op_ix in op_indexes)
        )

        con[req_name] = JuMP.@constraint(get_jump_model(container), lhs >= rhs)
    end
    return
end
