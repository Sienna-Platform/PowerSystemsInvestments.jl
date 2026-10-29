_is_resource(::PSIP.Technology) = false
_is_resource(::PSIP.ResourceTechnology) = true
_is_demand(::PSIP.Technology) = false
_is_demand(::PSIP.ProjectedDemand) = true
_is_line(::PSIP.Technology) = false
_is_line(::PSIP.TransmissionTechnology) = true

# Available technologies attached to a requirement, of the kind selected by `is_kind`
_contributing(p::PSIP.Portfolio, requirement::PSIP.Requirement, is_kind) = [
    t for t in PSIP.get_contributing_technologies(p, requirement) if
    is_kind(t) && PSIP.get_available(t)
]
_contributing_resources(p::PSIP.Portfolio, requirement::PSIP.Requirement) =
    _contributing(p, requirement, _is_resource)
_contributing_demands(p::PSIP.Portfolio, requirement::PSIP.Requirement) =
    _contributing(p, requirement, _is_demand)
_contributing_lines(p::PSIP.Portfolio, requirement::PSIP.Requirement) =
    _contributing(p, requirement, _is_line)

function _check_contributors(
    p::PSIP.Portfolio,
    requirement::PSIP.Requirement;
    demands::Bool,
)
    missing_kinds = String[]
    isempty(_contributing_resources(p, requirement)) && push!(missing_kinds, "resources")
    if demands && isempty(_contributing_demands(p, requirement))
        push!(missing_kinds, "demand technologies")
    end
    if !isempty(missing_kinds)
        error(
            "Requirement '$(PSIP.get_name(requirement))' has no available contributing " *
            "$(join(missing_kinds, " or ")).",
        )
    end
    return
end

# Regions (zonal) or nodes (nodal) of the contributing demand technologies of a requirement
_requirement_area(p::PSIP.Portfolio, requirement::PSIP.Requirement) = Set(
    PSIP.get_name(region) for d in _contributing_demands(p, requirement) for
    region in PSIP.get_region(d)
)

function _target_investment_period(time_mapping::TimeMapping, requirement::PSIP.Requirement)
    target_year = PSIP.get_target_year(requirement)
    period = findfirst(
        iv -> Dates.year(iv[1]) <= target_year <= Dates.year(iv[2]),
        get_investment_time_stamps(time_mapping),
    )
    if isnothing(period)
        error(
            "Requirement $(PSIP.get_name(requirement)) has target year $target_year, which " *
            "is not within any investment period of the capital model.",
        )
    end
    return period
end

# Present value at the base year of one unit paid in every year of an investment period
function _period_cost_factor(container::SingleOptimizationContainer, period::Int)
    inv_tuple = get_investment_time_stamps(get_time_mapping(container))[period]
    discount_rate = get_discount_rate(container)
    return investment_period_annuity_factor(discount_rate, inv_tuple) *
           (1.0 + discount_rate)^(get_base_year(container) - Dates.year(first(inv_tuple)))
end

_target_period_cost_factor(
    container::SingleOptimizationContainer,
    requirement::PSIP.Requirement,
) = _period_cost_factor(
    container,
    _target_investment_period(get_time_mapping(container), requirement),
)

# Warns that attached technologies of a kind do not contribute to a requirement
function _warn_ignored_contributors(
    technologies::Vector,
    requirement::PSIP.Requirement,
    kind::String,
)
    isempty(technologies) && return
    @warn "$(kind) $(join(PSIP.get_name.(technologies), ", ")) attached to requirement '$(PSIP.get_name(requirement))' do not contribute to it."
    return
end

# Shortfall variables of the requirements whose model uses slacks. A unit of shortfall in a
# target period costs the "slack_penalty" in every year of that period.
function _add_requirement_slacks!(
    container::SingleOptimizationContainer,
    requirements::Vector{T},
    requirement_model_vector::Vector{<:RequirementModel};
    meta::String=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: PSIP.Requirement}
    with_slacks = [
        (req, model) for (req, model) in zip(requirements, requirement_model_vector) if
        get_use_slacks(model)
    ]
    isempty(with_slacks) && return
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))
    slacks = add_variable_container!(
        container,
        RequirementSlackVariable(),
        T,
        [PSIP.get_name(req) for (req, _) in with_slacks];
        meta=meta,
    )
    for (req, model) in with_slacks
        name = PSIP.get_name(req)
        slacks[name] = JuMP.@variable(
            jump_model,
            lower_bound = 0.0,
            base_name = store_names ? "RequirementSlackVariable_{$(name)}" : "",
        )
        cost =
            get_attributes(model)["slack_penalty"] *
            _target_period_cost_factor(container, req)
        add_to_objective_operations_expression!(container, cost * slacks[name])
    end
    return
end

# Stores the duals of the constraints listed by the requirement models. The constraints of a
# requirement type have the formulation as meta when the type has several formulations.
function _add_requirement_duals!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{B},
    requirement_model_vector::Vector{<:RequirementModel},
) where {T <: PSIP.Requirement, B <: RequirementFormulation}
    constraints = get_constraints(container)
    for model in requirement_model_vector, constraint_type in get_duals(model)
        found = filter(
            k -> haskey(constraints, k),
            [
                ConstraintKey(constraint_type, T),
                ConstraintKey(constraint_type, T, string(B)),
            ],
        )
        if isempty(found)
            error("$(nameof(T)) has no $(nameof(constraint_type)) to take the duals of.")
        end
        container.duals[only(found)] = constraints[only(found)]
    end
    return
end

# Technology model of a contributing technology
function _contributor_model(
    names_to_model_map::Dict{String, TechnologyModel},
    req_name::String,
    technology::PSIP.Technology,
)
    name = PSIP.get_name(technology)
    if !haskey(names_to_model_map, name)
        error(
            "Requirement '$(req_name)' lists contributing technology '$(name)' " *
            "which has no technology model in the template.",
        )
    end
    return names_to_model_map[name]
end

# Operations formulation of a demand attached to a requirement. A demand without a model in
# the template has a fixed demand.
function _demand_formulation(
    names_to_model_map::Dict{String, TechnologyModel},
    d::PSIP.ProjectedDemand,
)
    name = PSIP.get_name(d)
    if haskey(names_to_model_map, name)
        return get_operations_formulation(names_to_model_map[name])()
    end
    return BasicDispatch()
end

# Weighted energy of a variable over the time steps of a representative period
function _weighted_energy(
    container::SingleOptimizationContainer,
    variable::T,
    ::Type{D},
    meta::String,
    name::String,
    op_ix::Int,
) where {T <: VariableType, D <: PSIP.Technology}
    values = get_variable(container, variable, D, meta)
    slices = get_consecutive_slices(get_time_mapping(container))[op_ix]
    return get_time_step_weight(container, op_ix) * sum(values[name, t] for t in slices)
end

# Eligible generation of a contributing resource: the output of supply technologies and the
# wind and solar output that co-located technologies deliver through their inverter. Storage
# only shifts energy.
function _add_eligible_generation!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.SupplyTechnology,
    meta::String,
    op_ix::Int,
) where {D <: PSIP.SupplyTechnology}
    generation = get_expression(container, WeightedEnergyGeneration(), D, meta)
    for name in get_variable_names(technology)
        JuMP.add_to_expression!(expression, generation[name, op_ix])
    end
    return
end

function _add_eligible_generation!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.ColocatedSupplyStorageTechnology,
    meta::String,
    op_ix::Int,
) where {D <: PSIP.ColocatedSupplyStorageTechnology}
    name = PSIP.get_name(technology)
    efficiency = get_inverter_efficiency(technology)
    for variable in (ActivePowerWindVariable(), ActivePowerSolarVariable())
        JuMP.add_to_expression!(
            expression,
            efficiency,
            _weighted_energy(container, variable, D, meta, name, op_ix),
        )
    end
    return
end

_add_eligible_generation!(
    ::JuMP.AffExpr,
    ::SingleOptimizationContainer,
    ::Type{<:PSIP.StorageTechnology},
    ::PSIP.StorageTechnology,
    ::String,
    ::Int,
) = nothing

# Losses of contributing storage, added to the demand
_add_storage_losses!(
    ::JuMP.AffExpr,
    ::SingleOptimizationContainer,
    ::Type{<:PSIP.SupplyTechnology},
    ::PSIP.SupplyTechnology,
    ::String,
    ::Int,
) = nothing

# Energy storage draws from the grid minus the energy it returns
function _add_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.StorageTechnology,
    meta::String,
    op_ix::Int,
) where {D <: PSIP.StorageTechnology}
    name = PSIP.get_name(technology)
    for (variable, sign) in
        ((ActiveInPowerVariable(), 1.0), (ActiveOutPowerVariable(), -1.0))
        JuMP.add_to_expression!(
            expression,
            sign,
            _weighted_energy(container, variable, D, meta, name, op_ix),
        )
    end
    return
end

# Co-located storage charges and discharges through the inverter
function _add_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.ColocatedSupplyStorageTechnology,
    meta::String,
    op_ix::Int,
) where {D <: PSIP.ColocatedSupplyStorageTechnology}
    name = PSIP.get_name(technology)
    efficiency = get_inverter_efficiency(technology)
    for (variable, coefficient) in (
        (ActivePowerChargeVariable(), 1.0 / efficiency),
        (ActivePowerDischargeVariable(), -efficiency),
    )
        JuMP.add_to_expression!(
            expression,
            coefficient,
            _weighted_energy(container, variable, D, meta, name, op_ix),
        )
    end
    return
end

# Eligible generation of every contributing resource of a requirement
function _add_eligible_generation!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    requirement::PSIP.Requirement,
    names_to_model_map::Dict{String, TechnologyModel},
    op_ix::Int,
)
    req_name = PSIP.get_name(requirement)
    for resource in _contributing_resources(p, requirement)
        tech_model = _contributor_model(names_to_model_map, req_name, resource)
        _add_eligible_generation!(
            expression,
            container,
            get_technology_type(tech_model),
            resource,
            string(get_operations_formulation(tech_model)),
            op_ix,
        )
    end
    return
end

# Weighted demand of the contributing demand technologies of a requirement, plus the losses
# of its contributing storage. The demand is gross, or with `served` net of unserved demand.
function _add_demand_and_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    requirement::PSIP.Requirement,
    names_to_model_map::Dict{String, TechnologyModel},
    op_ix::Int;
    served::Bool=false,
)
    time_slices = get_consecutive_slices(get_time_mapping(container))[op_ix]
    weight = get_time_step_weight(container, op_ix)
    demand = get_expression(container, DemandExpression(), PSIP.Portfolio)
    for d in _contributing_demands(p, requirement)
        for t in time_slices
            JuMP.add_to_expression!(expression, weight, demand[PSIP.get_name(d), t])
        end
        if served
            _add_unserved_demand!(
                _ -> expression,
                container,
                d,
                _demand_formulation(names_to_model_map, d),
                time_slices,
                -weight,
            )
        end
    end
    req_name = PSIP.get_name(requirement)
    for resource in _contributing_resources(p, requirement)
        tech_model = _contributor_model(names_to_model_map, req_name, resource)
        _add_storage_losses!(
            expression,
            container,
            get_technology_type(tech_model),
            resource,
            string(get_operations_formulation(tech_model)),
            op_ix,
        )
    end
    return
end
