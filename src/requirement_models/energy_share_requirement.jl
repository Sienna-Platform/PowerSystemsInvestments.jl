_supported_requirement_formulations(::Type{<:PSIP.EnergyShareRequirements}) =
    (RequirementEnergyShare,)

get_default_attributes(
    ::Type{<:PSIP.EnergyShareRequirements},
    ::Type{RequirementEnergyShare},
) = Dict{String, Any}("slack_penalty" => REQUIREMENT_SLACK_PENALTY)

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
    for req in requirements
        _check_contributors(p, req; demands=true)
    end
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

# Eligible generation of each policy in each representative period
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

# Demand plus storage losses of each policy in each representative period
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

# Over the target period: generation + slack >= generation_fraction_requirement * demand
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
