_is_resource(::PSIP.Technology) = false
_is_resource(::PSIP.ResourceTechnology) = true
_is_demand(::PSIP.Technology) = false
_is_demand(::PSIP.DemandTechnology) = true
_is_line(::PSIP.Technology) = false
_is_line(::PSIP.TransmissionTechnology) = true

"""
Return the available technologies attached to `requirement` that participate on
the generation side — `PSIP.ResourceTechnology` subtypes (`SupplyTechnology`,
`StorageTechnology`, `ColocatedSupplyStorageTechnology`). Generic over any
`PSIP.Requirement` so it is shared by all requirement models.
"""
function _contributing_resources(p::PSIP.Portfolio, requirement::PSIP.Requirement)
    return [
        t for t in PSIP.get_contributing_technologies(p, requirement) if
        _is_resource(t) && PSIP.get_available(t)
    ]
end

"""
Return the available technologies attached to `requirement` that participate on
the demand side — `PSIP.DemandTechnology` subtypes (`DemandRequirement`,
`DemandSideTechnology`). Generic over any `PSIP.Requirement`.
"""
function _contributing_demands(p::PSIP.Portfolio, requirement::PSIP.Requirement)
    return [
        t for t in PSIP.get_contributing_technologies(p, requirement) if
        _is_demand(t) && PSIP.get_available(t)
    ]
end

# Present value at the base year of one unit paid in every year of a requirement's target
# period
function _target_period_cost_factor(
    container::SingleOptimizationContainer,
    requirement::PSIP.Requirement,
)
    time_mapping = get_time_mapping(container)
    inv_tuple = get_investment_time_stamps(time_mapping)[_target_investment_period(
        time_mapping,
        requirement,
    )]
    discount_rate = get_discount_rate(container)
    return investment_period_annuity_factor(discount_rate, inv_tuple) *
           (1.0 + discount_rate)^(get_base_year(container) - Dates.year(first(inv_tuple)))
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
        keys = filter(
            k -> haskey(constraints, k),
            [
                ConstraintKey(constraint_type, T),
                ConstraintKey(constraint_type, T, string(B)),
            ],
        )
        if isempty(keys)
            error("$(nameof(T)) has no $(nameof(constraint_type)) to take the duals of.")
        end
        container.duals[only(keys)] = constraints[only(keys)]
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
# wind and solar output of co-located technologies. Storage only shifts energy.
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
    for variable in (ActivePowerWindVariable(), ActivePowerSolarVariable())
        JuMP.add_to_expression!(
            expression,
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

# Losses (charge minus discharge) of contributing storage, added to the demand
_add_storage_losses!(
    ::JuMP.AffExpr,
    ::SingleOptimizationContainer,
    ::Type{<:PSIP.SupplyTechnology},
    ::PSIP.SupplyTechnology,
    ::String,
    ::Int,
) = nothing

function _add_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.StorageTechnology,
    meta::String,
    op_ix::Int,
) where {D <: PSIP.StorageTechnology}
    _add_storage_losses!(
        expression,
        container,
        D,
        PSIP.get_name(technology),
        meta,
        op_ix,
        ActiveInPowerVariable(),
        ActiveOutPowerVariable(),
    )
    return
end

function _add_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    technology::PSIP.ColocatedSupplyStorageTechnology,
    meta::String,
    op_ix::Int,
) where {D <: PSIP.ColocatedSupplyStorageTechnology}
    _add_storage_losses!(
        expression,
        container,
        D,
        PSIP.get_name(technology),
        meta,
        op_ix,
        ActivePowerChargeVariable(),
        ActivePowerDischargeVariable(),
    )
    return
end

function _add_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    ::Type{D},
    name::String,
    meta::String,
    op_ix::Int,
    charge::VariableType,
    discharge::VariableType,
) where {D <: PSIP.Technology}
    JuMP.add_to_expression!(
        expression,
        _weighted_energy(container, charge, D, meta, name, op_ix),
    )
    JuMP.add_to_expression!(
        expression,
        -1.0,
        _weighted_energy(container, discharge, D, meta, name, op_ix),
    )
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

# Weighted demand of the contributing demand technologies of a requirement, read from their
# "ops_demand" time series, plus the losses of its contributing storage
function _add_demand_and_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    requirement::PSIP.Requirement,
    names_to_model_map::Dict{String, TechnologyModel},
    op_ix::Int,
)
    time_mapping = get_time_mapping(container)
    first_time_stamp =
        get_time_stamps(time_mapping)[first(get_consecutive_slices(time_mapping)[op_ix])]
    weight = get_time_step_weight(container, op_ix)
    for d in _contributing_demands(p, requirement)
        time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
        check_initial_timestamp(time_series, d, first_time_stamp, op_ix)
        # Load data is in MW
        JuMP.add_to_expression!(
            expression,
            weight * sum(TimeSeries.values(time_series.data)),
        )
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

_contributing_lines(p::PSIP.Portfolio, requirement::PSIP.Requirement) = [
    t for t in PSIP.get_contributing_technologies(p, requirement) if
    _is_line(t) && PSIP.get_available(t)
]

# Regions (zonal) or nodes (nodal) of the contributing demand technologies of a requirement
_requirement_area(p::PSIP.Portfolio, requirement::PSIP.Requirement) = Set(
    PSIP.get_name(region) for d in _contributing_demands(p, requirement) for
    region in PSIP.get_region(d)
)
