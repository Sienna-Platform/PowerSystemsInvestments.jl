_supported_requirement_formulations(::Type{<:PSIP.CarbonCaps}) = (
    RequirementCarbonCapMass,
    RequirementCarbonCapDemandRate,
    RequirementCarbonCapGenerationRate,
)
_supported_requirement_formulations(::Type{<:PSIP.CarbonTax}) = (RequirementCarbonTax,)

_supports_slacks(::Type{RequirementCarbonTax}) = false

get_default_attributes(::Type{<:PSIP.CarbonCaps}, ::Type{<:CarbonCapFormulation}) =
    Dict{String, Any}("slack_penalty" => REQUIREMENT_SLACK_PENALTY)

# Only technologies whose fuel consumption is modeled emit
_has_fuel_consumption(::PSIP.Technology) = false
_has_fuel_consumption(d::PSIP.SupplyTechnology) = has_fuel_curve(d)

_emitters(p::PSIP.Portfolio, requirement::PSIP.Requirement) =
    filter(_has_fuel_consumption, _contributing_resources(p, requirement))

# Carbon intensity (tCO2/MMBtu) of the fuel of a technology
function _carbon_intensity(technology::PSIP.SupplyTechnology)
    co2 = PSIP.get_co2(technology)
    isempty(co2) && return 0.0
    fuels = PSIP.get_fuel(technology)
    if length(fuels) != 1
        error(
            "Technology $(PSIP.get_name(technology)) has carbon intensities and " *
            "$(length(fuels)) fuels; emissions are computed for a single fuel.",
        )
    end
    return get(co2, only(fuels), 0.0)
end

function _check_emitters(p::PSIP.Portfolio, requirement::PSIP.Requirement)
    if isempty(_emitters(p, requirement))
        error(
            "Requirement '$(PSIP.get_name(requirement))' has no available contributing " *
            "technology with a fuel curve, so it has no emissions.",
        )
    end
    return
end

# The demand rate cap is set by the policy's demand
_uses_demands(::Type{<:RequirementFormulation}) = false
_uses_demands(::Type{RequirementCarbonCapDemandRate}) = true

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
    T <: Union{PSIP.CarbonCaps, PSIP.CarbonTax},
    B <: Union{CarbonCapFormulation, RequirementCarbonTax},
    X <: RequirementModel,
}
    requirements = [PSIP.get_requirement(T, p, n) for n in names]
    for req in requirements
        _check_emitters(p, req)
        _check_contributors(p, req; demands=_uses_demands(B))
    end
    add_expression!(
        container,
        WeightedCarbonEmissions(),
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
) where {T <: PSIP.CarbonCaps, B <: CarbonCapFormulation, X <: RequirementModel}
    requirements = [PSIP.get_requirement(T, p, n) for n in names]
    add_constraints!(
        container,
        CarbonCapConstraint(),
        p,
        requirements,
        B(),
        names_to_model_map,
        requirement_model_vector,
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
) where {T <: PSIP.CarbonTax, B <: RequirementCarbonTax, X <: RequirementModel}
    time_mapping = get_time_mapping(container)
    map_to_op = get_investment_map_to_operational_slices(time_mapping)
    emissions = get_expression(container, WeightedCarbonEmissions(), T, string(B))
    for name in names
        req = PSIP.get_requirement(T, p, name)
        op_indexes = map_to_op[_target_investment_period(time_mapping, req)]
        cost =
            PSIP.get_tax_dollars_per_ton(req) * _target_period_cost_factor(container, req)
        add_to_objective_operations_expression!(
            container,
            cost * sum(emissions[name, op_ix] for op_ix in op_indexes),
        )
    end
    return
end

# Yearly emissions of each policy in each representative period: carbon intensity times
# fuel consumption of its technologies with fuel curves
function add_expression!(
    container::SingleOptimizationContainer,
    ::WeightedCarbonEmissions,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    ::B,
    names_to_model_map::Dict{String, TechnologyModel},
) where {T <: PSIP.Requirement, B <: RequirementFormulation}
    time_mapping = get_time_mapping(container)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    weights = get_operational_weights(container)
    expression = add_expression_container!(
        container,
        WeightedCarbonEmissions(),
        T,
        PSIP.get_name.(requirements),
        operational_indexes;
        meta=string(B),
    )
    for req in requirements
        req_name = PSIP.get_name(req)
        for op_ix in operational_indexes
            expression[req_name, op_ix] = JuMP.AffExpr(0.0)
        end
        for d in _emitters(p, req)
            intensity = _carbon_intensity(d)
            iszero(intensity) && continue
            tech_model = _contributor_model(names_to_model_map, req_name, d)
            fuel = get_expression(
                container,
                FuelConsumptionExpression(),
                get_technology_type(tech_model),
                string(get_operations_formulation(tech_model)),
            )
            for op_ix in operational_indexes, name in get_variable_names(d)
                for t in consecutive_slices[op_ix]
                    JuMP.add_to_expression!(
                        expression[req_name, op_ix],
                        intensity * weights[op_ix],
                        fuel[name, t],
                    )
                end
            end
        end
    end
    return
end

# Yearly emission limit of a carbon cap in the operational indexes of its target period
function _add_carbon_limit!(
    limit::JuMP.AffExpr,
    ::SingleOptimizationContainer,
    ::PSIP.Portfolio,
    requirement::PSIP.CarbonCaps,
    ::RequirementCarbonCapMass,
    ::Dict{String, TechnologyModel},
    ::Vector{Int},
)
    JuMP.add_to_expression!(limit, 1e6 * PSIP.get_max_mtons(requirement))
    return
end

function _add_carbon_limit!(
    limit::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    requirement::PSIP.CarbonCaps,
    ::RequirementCarbonCapDemandRate,
    names_to_model_map::Dict{String, TechnologyModel},
    op_indexes::Vector{Int},
)
    demand = JuMP.AffExpr(0.0)
    for op_ix in op_indexes
        _add_demand_and_storage_losses!(
            demand,
            container,
            p,
            requirement,
            names_to_model_map,
            op_ix,
        )
    end
    JuMP.add_to_expression!(limit, PSIP.get_max_tons_mwh(requirement), demand)
    return
end

function _add_carbon_limit!(
    limit::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    requirement::PSIP.CarbonCaps,
    ::RequirementCarbonCapGenerationRate,
    names_to_model_map::Dict{String, TechnologyModel},
    op_indexes::Vector{Int},
)
    generation = JuMP.AffExpr(0.0)
    for op_ix in op_indexes
        _add_eligible_generation!(
            generation,
            container,
            p,
            requirement,
            names_to_model_map,
            op_ix,
        )
    end
    JuMP.add_to_expression!(limit, PSIP.get_max_tons_mwh(requirement), generation)
    return
end

# Over the target period: emissions <= limit (see `CarbonCapFormulation`) + slack
function add_constraints!(
    container::SingleOptimizationContainer,
    ::CarbonCapConstraint,
    p::PSIP.Portfolio,
    requirements::Vector{T},
    formulation::B,
    names_to_model_map::Dict{String, TechnologyModel},
    requirement_model_vector::Vector{X},
) where {T <: PSIP.CarbonCaps, B <: CarbonCapFormulation, X <: RequirementModel}
    time_mapping = get_time_mapping(container)
    jump_model = get_jump_model(container)
    map_to_op = get_investment_map_to_operational_slices(time_mapping)
    meta = string(B)
    emissions = get_expression(container, WeightedCarbonEmissions(), T, meta)
    _add_requirement_slacks!(container, requirements, requirement_model_vector; meta=meta)
    slacks = if has_container_key(container, RequirementSlackVariable, T, meta)
        get_variable(container, RequirementSlackVariable(), T, meta)
    else
        nothing
    end
    con = add_constraints_container!(
        container,
        CarbonCapConstraint(),
        T,
        PSIP.get_name.(requirements);
        meta=meta,
    )
    for req in requirements
        req_name = PSIP.get_name(req)
        op_indexes = map_to_op[_target_investment_period(time_mapping, req)]
        limit = JuMP.AffExpr(0.0)
        _add_carbon_limit!(
            limit,
            container,
            p,
            req,
            formulation,
            names_to_model_map,
            op_indexes,
        )
        if !isnothing(slacks) && req_name in axes(slacks, 1)
            JuMP.add_to_expression!(limit, slacks[req_name])
        end
        con[req_name] = JuMP.@constraint(
            jump_model,
            sum(emissions[req_name, op_ix] for op_ix in op_indexes) <= limit
        )
    end
    return
end
