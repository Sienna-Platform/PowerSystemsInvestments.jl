_is_resource(::PSIP.Technology) = false
_is_resource(::PSIP.ResourceTechnology) = true
_is_demand(::PSIP.Technology) = false
_is_demand(::PSIP.DemandTechnology) = true
_is_line(::PSIP.Technology) = false
_is_line(::PSIP.TransmissionTechnology) = true

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
    requirement::PSIP.Requirement,
    names_to_model_map::Dict{String, TechnologyModel};
    demands::Bool,
)
    resources = _contributing_resources(p, requirement)
    demand_technologies = demands ? _contributing_demands(p, requirement) : []
    missing_kinds = String[]
    isempty(resources) && push!(missing_kinds, "resources")
    demands && isempty(demand_technologies) && push!(missing_kinds, "demand technologies")
    if !isempty(missing_kinds)
        error(
            "Requirement '$(PSIP.get_name(requirement))' has no available contributing " *
            "$(join(missing_kinds, " or ")).",
        )
    end
    for technology in [resources; demand_technologies]
        _contributor_model(names_to_model_map, PSIP.get_name(requirement), technology)
    end
    return
end

function _target_investment_period(time_mapping::TimeMapping, requirement::PSIP.Requirement)
    target_year = PSIP.get_target_year(requirement)
    period = findfirst(
        iv -> Dates.year(iv[1]) <= target_year <= Dates.year(iv[2]),
        get_investment_time_stamps(time_mapping),
    )
    if isnothing(period)
        throw(
            IS.ConflictingInputsError(
                "Requirement $(PSIP.get_name(requirement)) has target year $target_year, " *
                "which is not within any investment period of the capital model",
            ),
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

function _warn_ignored_contributors(
    technologies::Vector,
    requirement::PSIP.Requirement,
    kind::String,
)
    isempty(technologies) && return
    @warn "$(kind) $(join(PSIP.get_name.(technologies), ", ")) attached to requirement '$(PSIP.get_name(requirement))' do not contribute to it."
    return
end

# Slack container of the requirements whose model uses slacks; nothing when none does
function _add_slack_container!(
    container::SingleOptimizationContainer,
    requirements::Vector{T},
    requirement_model_vector::Vector{<:RequirementModel},
    axs...;
    meta::String=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: PSIP.Requirement}
    names = [
        PSIP.get_name(req) for
        (req, model) in zip(requirements, requirement_model_vector) if get_use_slacks(model)
    ]
    isempty(names) && return nothing
    return add_variable_container!(
        container,
        RequirementSlackVariable(),
        T,
        names,
        axs...;
        meta=meta,
    )
end

function _add_requirement_slack!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    slacks,
    cost::Float64,
    index...,
)
    store_names = get_store_variable_names(get_settings(container))
    slack = JuMP.@variable(
        get_jump_model(container),
        lower_bound = 0.0,
        base_name =
            store_names ? "RequirementSlackVariable_{$(join(index, ", "))}" : "",
    )
    slacks[index...] = slack
    JuMP.add_to_expression!(expression, slack)
    add_to_objective_operations_expression!(container, cost * slack)
    return
end

# Constraints have the formulation as meta when their requirement type has several
function _add_requirement_duals!(
    container::SingleOptimizationContainer,
    requirement_map::Dict{Tuple{Type, Type}, Vector{String}},
    requirement_names_to_model_map::Dict{String, RequirementModel},
)
    constraints = get_constraints(container)
    for ((T, B), names) in requirement_map, name in names
        for constraint_type in get_duals(requirement_names_to_model_map[name])
            found = filter(
                k -> haskey(constraints, k),
                [
                    ConstraintKey(constraint_type, T),
                    ConstraintKey(constraint_type, T, string(B)),
                ],
            )
            if isempty(found)
                throw(
                    ArgumentError(
                        "$(nameof(T)) has no $(nameof(constraint_type)) to take the duals of",
                    ),
                )
            end
            container.duals[only(found)] = constraints[only(found)]
        end
    end
    return
end

function _contributor_model(
    names_to_model_map::Dict{String, TechnologyModel},
    req_name::String,
    technology::PSIP.Technology,
)
    name = PSIP.get_name(technology)
    if !haskey(names_to_model_map, name)
        throw(
            IS.ConflictingInputsError(
                "Requirement '$(req_name)' lists contributing technology '$(name)' " *
                "which has no technology model in the template",
            ),
        )
    end
    return names_to_model_map[name]
end

function _weighted_energy(
    container::SingleOptimizationContainer,
    variable::VariableType,
    tech_model::TechnologyModel{D},
    name::String,
    op_ix::Int,
) where {D <: PSIP.Technology}
    meta = string(get_operations_formulation(tech_model))
    values = get_variable(container, variable, D, meta)
    slices = get_consecutive_slices(get_time_mapping(container))[op_ix]
    return get_time_step_weight(container, op_ix) * sum(values[name, t] for t in slices)
end

function _add_eligible_generation!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    technology::PSIP.SupplyTechnology,
    tech_model::TechnologyModel{D},
    op_ix::Int,
) where {D <: PSIP.SupplyTechnology}
    meta = string(get_operations_formulation(tech_model))
    generation = get_expression(container, WeightedEnergyGeneration(), D, meta)
    for name in get_variable_names(technology)
        JuMP.add_to_expression!(expression, generation[name, op_ix])
    end
    return
end

function _add_eligible_generation!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    technology::PSIP.ColocatedSupplyStorageTechnology,
    tech_model::TechnologyModel,
    op_ix::Int,
)
    name = PSIP.get_name(technology)
    efficiency = get_inverter_efficiency(technology)
    for variable in (ActivePowerWindVariable(), ActivePowerSolarVariable())
        JuMP.add_to_expression!(
            expression,
            efficiency,
            _weighted_energy(container, variable, tech_model, name, op_ix),
        )
    end
    return
end

_add_eligible_generation!(
    ::JuMP.AffExpr,
    ::SingleOptimizationContainer,
    ::PSIP.StorageTechnology,
    ::TechnologyModel,
    ::Int,
) = nothing

# Losses of contributing storage, added to the demand
_add_storage_losses!(
    ::JuMP.AffExpr,
    ::SingleOptimizationContainer,
    ::PSIP.SupplyTechnology,
    ::TechnologyModel,
    ::Int,
) = nothing

# Energy storage draws from the grid minus the energy it returns
function _add_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    technology::PSIP.StorageTechnology,
    tech_model::TechnologyModel,
    op_ix::Int,
)
    name = PSIP.get_name(technology)
    for (variable, sign) in
        ((ActiveInPowerVariable(), 1.0), (ActiveOutPowerVariable(), -1.0))
        JuMP.add_to_expression!(
            expression,
            sign,
            _weighted_energy(container, variable, tech_model, name, op_ix),
        )
    end
    return
end

# Co-located storage charges and discharges through the inverter
function _add_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    technology::PSIP.ColocatedSupplyStorageTechnology,
    tech_model::TechnologyModel,
    op_ix::Int,
)
    name = PSIP.get_name(technology)
    efficiency = get_inverter_efficiency(technology)
    for (variable, coefficient) in (
        (ActivePowerChargeVariable(), 1.0 / efficiency),
        (ActivePowerDischargeVariable(), -efficiency),
    )
        JuMP.add_to_expression!(
            expression,
            coefficient,
            _weighted_energy(container, variable, tech_model, name, op_ix),
        )
    end
    return
end

function _add_net_injection!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    tech_model::TechnologyModel{D},
    name::String,
    t::Int,
) where {D <: Union{PSIP.StorageTechnology, PSIP.ColocatedSupplyStorageTechnology}}
    meta = string(get_operations_formulation(tech_model))
    injection = get_variable(container, ActiveOutPowerVariable(), D, meta)
    withdrawal = get_variable(container, ActiveInPowerVariable(), D, meta)
    JuMP.add_to_expression!(expression, injection[name, t])
    JuMP.add_to_expression!(expression, -1.0, withdrawal[name, t])
    return
end

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
        _add_eligible_generation!(expression, container, resource, tech_model, op_ix)
    end
    return
end

# Summed demand (MW) of a requirement's demand technologies in a representative period
function _requirement_demand(
    p::PSIP.Portfolio,
    requirement::PSIP.Requirement,
    time_mapping::TimeMapping,
    op_ix::Int,
)
    demand = zeros(length(get_consecutive_slices(time_mapping)[op_ix]))
    for d in _contributing_demands(p, requirement)
        demand .+= TimeSeries.values(retrieve_ops_time_series(d, op_ix, time_mapping).data)
    end
    return demand
end

function _add_demand_and_storage_losses!(
    expression::JuMP.AffExpr,
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    requirement::PSIP.Requirement,
    names_to_model_map::Dict{String, TechnologyModel},
    op_ix::Int,
)
    demand = _requirement_demand(p, requirement, get_time_mapping(container), op_ix)
    JuMP.add_to_expression!(
        expression,
        get_time_step_weight(container, op_ix) * sum(demand),
    )
    req_name = PSIP.get_name(requirement)
    for resource in _contributing_resources(p, requirement)
        tech_model = _contributor_model(names_to_model_map, req_name, resource)
        _add_storage_losses!(expression, container, resource, tech_model, op_ix)
    end
    return
end
