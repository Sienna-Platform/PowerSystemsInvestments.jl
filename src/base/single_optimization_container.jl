struct PrimalValuesCache
    variables_cache::Dict{VariableKey, AbstractArray}
    expressions_cache::Dict{ExpressionKey, AbstractArray}
end

function PrimalValuesCache()
    return PrimalValuesCache(
        Dict{VariableKey, AbstractArray}(),
        Dict{ExpressionKey, AbstractArray}(),
    )
end

function Base.isempty(pvc::PrimalValuesCache)
    return isempty(pvc.variables_cache) && isempty(pvc.expressions_cache)
end

Base.@kwdef mutable struct SingleOptimizationContainer <:
                           ISOPT.AbstractOptimizationContainer
    JuMPmodel::JuMP.Model
    time_mapping::TimeMapping
    settings::Settings
    settings_copy::Settings
    variables::Dict{ISOPT.VariableKey, AbstractArray}
    aux_variables::Dict{ISOPT.AuxVarKey, AbstractArray}
    duals::Dict{ISOPT.ConstraintKey, AbstractArray}
    constraints::Dict{ISOPT.ConstraintKey, AbstractArray}
    objective_function::ObjectiveFunction
    expressions::Dict{ISOPT.ExpressionKey, AbstractArray}
    primal_values_cache::PrimalValuesCache
    operational_weights::Union{Nothing, Vector{Float64}}
    base_year::Int
    discount_rate::Float64
    inflation_rate::Float64
    interest_rate::Float64
    infeasibility_conflict::Dict{Symbol, Array}
    optimizer_stats::ISOPT.OptimizerStats
    metadata::ISOPT.OptimizationContainerMetadata
end

function SingleOptimizationContainer(
    settings::Settings,
    jump_model::Union{Nothing, JuMP.Model},
)
    if jump_model !== nothing && get_direct_mode_optimizer(settings)
        throw(
            IS.ConflictingInputsError(
                "Externally provided JuMP models are not compatible with the direct model keyword argument. Use JuMP.direct_model before passing the custom model",
            ),
        )
    end

    return SingleOptimizationContainer(
        jump_model === nothing ? JuMP.Model() : jump_model,
        TimeMapping(nothing),
        settings,
        copy_for_serialization(settings),
        Dict{VariableKey, AbstractArray}(),
        Dict{AuxVarKey, AbstractArray}(),
        Dict{ConstraintKey, AbstractArray}(),
        Dict{ConstraintKey, AbstractArray}(),
        ObjectiveFunction(),
        Dict{ExpressionKey, AbstractArray}(),
        PrimalValuesCache(),
        nothing,
        2020,
        0.0,
        0.0,
        0.0,
        Dict{Symbol, Array}(),
        ISOPT.OptimizerStats(),
        ISOPT.OptimizationContainerMetadata(),
    )
end

built_for_recurrent_solves(container::SingleOptimizationContainer) =
    container.built_for_recurrent_solves

get_default_time_series_type(container::SingleOptimizationContainer) =
    container.default_time_series_type
get_duals(container::SingleOptimizationContainer) = container.duals
get_expressions(container::SingleOptimizationContainer) = container.expressions
get_initial_conditions(container::SingleOptimizationContainer) =
    container.initial_conditions
get_initial_conditions_data(container::SingleOptimizationContainer) =
    container.initial_conditions_data
get_initial_time(container::SingleOptimizationContainer) =
    get_initial_time(container.settings)
get_jump_model(container::SingleOptimizationContainer) = container.JuMPmodel
get_metadata(container::SingleOptimizationContainer) = container.metadata
get_optimizer_stats(container::SingleOptimizationContainer) = container.optimizer_stats
get_resolution(container::SingleOptimizationContainer) = get_resolution(container.settings)
get_settings(container::SingleOptimizationContainer) = container.settings
get_time_mapping(container::SingleOptimizationContainer) = container.time_mapping
get_operational_weights(container::SingleOptimizationContainer) =
    container.operational_weights
get_base_year(container::SingleOptimizationContainer) = container.base_year
get_discount_rate(container::SingleOptimizationContainer) = container.discount_rate
get_inflation_rate(container::SingleOptimizationContainer) = container.inflation_rate
get_interest_rate(container::SingleOptimizationContainer) = container.interest_rate
get_variables(container::SingleOptimizationContainer) = container.variables

set_initial_conditions_data!(container::SingleOptimizationContainer, data) =
    container.initial_conditions_data = data
get_objective_expression(container::SingleOptimizationContainer) =
    container.objective_function
is_synchronized(container::SingleOptimizationContainer) =
    container.objective_function.synchronized
set_time_mapping!(container::SingleOptimizationContainer, time_mapping::TimeMapping) =
    container.time_mapping = time_mapping
set_operational_weights!(
    container::SingleOptimizationContainer,
    operational_weights::Union{Nothing, Vector{Float64}},
) = container.operational_weights = operational_weights
set_base_year!(container::SingleOptimizationContainer, base_year::Int) =
    container.base_year = base_year
set_discount_rate!(container::SingleOptimizationContainer, discount_rate::Float64) =
    container.discount_rate = discount_rate
set_inflation_rate!(container::SingleOptimizationContainer, inflation_rate::Float64) =
    container.inflation_rate = inflation_rate
set_interest_rate!(container::SingleOptimizationContainer, interest_rate::Float64) =
    container.interest_rate = interest_rate

get_aux_variables(container::SingleOptimizationContainer) = container.aux_variables
get_base_power(container::SingleOptimizationContainer) = container.base_power
get_constraints(container::SingleOptimizationContainer) = container.constraints

function is_milp(container::SingleOptimizationContainer)::Bool
    !supports_milp(container) && return false
    if !isempty(
        JuMP.all_constraints(get_jump_model(container), JuMP.VariableRef, JuMP.MOI.ZeroOne),
    )
        return true
    end
    return false
end

function supports_milp(container::SingleOptimizationContainer)
    jump_model = get_jump_model(container)
    return supports_milp(jump_model)
end

# Dispatch helpers for extracting operational and feasibility periods from different operation models
function _shift_periods_to_year(periods::Vector{Vector{Dates.DateTime}}, target_year::Int)
    # Shift all DateTimes in periods to match target_year while preserving month/day/hour
    if isempty(periods)
        return periods
    end
    first_dt = first(first(periods))
    year_diff = target_year - Dates.year(first_dt)
    if year_diff == 0
        return periods
    end
    return [[dt + Dates.Year(year_diff) for dt in period] for period in periods]
end

_get_rep_series(::AggregateOperatingCost, f, target_year::Int=2025) = _shift_periods_to_year(_get_sample_periods(f), target_year)
_get_rep_series(op::OperationalRepresentativeDays, _feas_model, target_year::Int=2025) = _shift_periods_to_year(op.representative_series, target_year)
_get_weights(::AggregateOperatingCost, f) = ones(length(_get_sample_periods(f)))
_get_weights(op::OperationalRepresentativeDays, _feas_model) = op.series_weights
_get_sample_periods(f::RepresentativePeriods) = f.sample_periods
_get_sample_periods(::Any) = Vector{Vector{Dates.DateTime}}()

function _finalize_jump_model!(container::SingleOptimizationContainer, settings::Settings)
    @debug "Instantiating the JuMP model" _group = LOG_GROUP_OPTIMIZATION_CONTAINER

    if get_direct_mode_optimizer(settings)
        optimizer = () -> MOI.instantiate(get_optimizer(settings))
        container.JuMPmodel = JuMP.direct_model(optimizer())
    elseif get_optimizer(settings) === nothing
        @debug "The optimization model has no optimizer attached" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
    else
        JuMP.set_optimizer(get_jump_model(container), get_optimizer(settings))
    end

    JuMPmodel = get_jump_model(container)

    JuMP.set_string_names_on_creation(JuMPmodel, get_store_variable_names(settings))

    @debug begin
        JuMP.set_string_names_on_creation(JuMPmodel, true)
    end
    if get_optimizer_solve_log_print(settings)
        JuMP.unset_silent(JuMPmodel)
        @debug "optimizer unset to silent" _group = LOG_GROUP_OPTIMIZATION_CONTAINER
    else
        JuMP.set_silent(JuMPmodel)
        @debug "optimizer set to silent" _group = LOG_GROUP_OPTIMIZATION_CONTAINER
    end
    return
end

function init_optimization_container!(
    container::SingleOptimizationContainer,
    template::InvestmentModelTemplate,
    portfolio::PSIP.Portfolio,
)
    # The order of operations matter
    transport_model = get_transport_model(template)
    settings = get_settings(container)

    # Update Time Mapping
    capital_model = get_capital_model(template)
    operation_model = get_operation_model(template)
    feasibility_model = get_feasibility_model(template)

    # Extract target year from capital model for date shifting
    target_year = if !isempty(capital_model.investment_years)
        Dates.year(first(capital_model.investment_years)[1])
    else
        Dates.year(capital_model.base_year)
    end

    rep_series = _get_rep_series(operation_model, feasibility_model, target_year)
    weights = _get_weights(operation_model, feasibility_model)
    sample_periods = _shift_periods_to_year(_get_sample_periods(feasibility_model), target_year)
    time_map = TimeMapping(capital_model.investment_years, rep_series, sample_periods)
    set_time_mapping!(container, time_map)
    set_operational_weights!(container, weights)
    # Set Financial Data in Container from Portfolio
    set_base_year!(container, PSIP.get_base_year(portfolio))
    set_discount_rate!(container, PSIP.get_discount_rate(portfolio))
    set_inflation_rate!(container, PSIP.get_inflation_rate(portfolio))
    set_interest_rate!(container, PSIP.get_interest_rate(portfolio))

    stats = get_optimizer_stats(container)
    stats.detailed_stats = get_detailed_optimizer_stats(settings)

    _finalize_jump_model!(container, settings)
    return
end

function check_optimization_container(container::SingleOptimizationContainer)
    container.settings_copy = copy_for_serialization(container.settings)
    return
end

function _assign_container!(container::Dict, key::OptimizationContainerKey, value)
    if haskey(container, key)
        @error "$(IS.Optimization.encode_key(key)) is already stored" sort!(
            IS.Optimization.encode_key.(keys(container)),
        )
        throw(IS.InvalidValue("$key is already stored"))
    end
    container[key] = value
    return
end

function has_container_key(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = ExpressionKey(T, U, meta)
    return haskey(container.expressions, key)
end

function has_container_key(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: VariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = VariableKey(T, U, meta)
    return haskey(container.variables, key)
end

function has_container_key(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: AuxVariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = AuxVarKey(T, U, meta)
    return haskey(container.aux_variables, key)
end

function has_container_key(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = ConstraintKey(T, U, meta)
    return haskey(container.constraints, key)
end

####################################### Variable Container #################################
function _add_variable_container!(
    container::SingleOptimizationContainer,
    var_key::VariableKey,
    sparse::Bool,
    axs...,
)
    if sparse
        var_container = sparse_container_spec(JuMP.VariableRef, axs...)
    else
        var_container = container_spec(JuMP.VariableRef, axs...)
    end
    _assign_container!(container.variables, var_key, var_container)
    return var_container
end

function add_variable_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    axs...;
    sparse=false,
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: VariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    var_key = VariableKey(T, U, meta)
    return _add_variable_container!(container, var_key, sparse, axs...)
end

function add_variable_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    meta::String,
    axs...;
    sparse=false,
) where {T <: VariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    var_key = VariableKey(T, U, meta)
    return _add_variable_container!(container, var_key, sparse, axs...)
end

function _get_pwl_variables_container()
    contents = Dict{Tuple{String, Int, Int}, Any}()
    return SparseAxisArray(contents)
end

function add_variable_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U};
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: SparseVariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    var_key = VariableKey(T, U, meta)
    _assign_container!(container.variables, var_key, _get_pwl_variables_container())
    return container.variables[var_key]
end

# Extended methods for PSY component types (device models)
function add_variable_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    axs...;
    sparse=false,
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: VariableType, U <: PSY.Component}
    var_key = VariableKey(T, U, meta)
    return _add_variable_container!(container, var_key, sparse, axs...)
end

function add_variable_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    meta::String,
    axs...;
    sparse=false,
) where {T <: VariableType, U <: PSY.Component}
    var_key = VariableKey(T, U, meta)
    return _add_variable_container!(container, var_key, sparse, axs...)
end

function get_variable_keys(container::SingleOptimizationContainer)
    return collect(keys(container.variables))
end

function get_variable(container::SingleOptimizationContainer, key::VariableKey)
    var = get(container.variables, key, nothing)
    if var === nothing
        name = IS.Optimization.encode_key(key)
        keys = IS.Optimization.encode_key.(get_variable_keys(container))
        throw(IS.InvalidValue("variable $name is not stored. $keys"))
    end
    return var
end

function get_variable(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    meta::String=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: VariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_variable(container, VariableKey(T, U, meta))
end

##################################### Constraint Container #################################
function _add_constraints_container!(
    container::SingleOptimizationContainer,
    cons_key::ConstraintKey,
    axs...;
    sparse=false,
)
    if sparse
        cons_container = sparse_container_spec(JuMP.ConstraintRef, axs...)
    else
        cons_container = container_spec(JuMP.ConstraintRef, axs...)
    end
    _assign_container!(container.constraints, cons_key, cons_container)
    return cons_container
end

function add_constraints_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    axs...;
    sparse=false,
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    cons_key = ConstraintKey(T, U, meta)
    return _add_constraints_container!(container, cons_key, axs...; sparse=sparse)
end

# Extended method for PSY component types (device models)
function add_constraints_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    axs...;
    sparse=false,
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: PSY.Component}
    cons_key = ConstraintKey(T, U, meta)
    return _add_constraints_container!(container, cons_key, axs...; sparse=sparse)
end

function get_constraint_keys(container::SingleOptimizationContainer)
    return collect(keys(container.constraints))
end

function get_constraint(container::SingleOptimizationContainer, key::ConstraintKey)
    var = get(container.constraints, key, nothing)
    if var === nothing
        name = IS.Optimization.encode_key(key)
        keys = IS.Optimization.encode_key.(get_constraint_keys(container))
        throw(IS.InvalidValue("constraint $name is not stored. $keys"))
    end

    return var
end

function get_constraint(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    meta::String=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_constraint(container, ConstraintKey(T, U, meta))
end

# TODO: Duals
#=
function read_duals(container::SingleOptimizationContainer)
    return Dict(k => to_dataframe(jump_value.(v), k) for (k, v) in get_duals(container))
end
=#

##################################### Expression Container #################################

function _add_to_jump_expression!(
    expression::T,
    value::Float64,
) where {T <: JuMP.AbstractJuMPScalar}
    JuMP.add_to_expression!(expression, value)
    return
end

function _add_to_jump_expression!(
    expression::T,
    parameter::Float64,
    multiplier::Float64,
) where {T <: JuMP.AbstractJuMPScalar}
    _add_to_jump_expression!(expression, parameter * multiplier)
    return
end

function _add_to_jump_expression!(
    expression::T,
    var::JuMP.VariableRef,
    multiplier::Float64,
) where {T <: JuMP.AbstractJuMPScalar}
    JuMP.add_to_expression!(expression, multiplier, var)
    return
end

function _add_to_jump_expression!(
    expression::T,
    var::JuMP.AffExpr,
    multiplier::Float64,
) where {T <: JuMP.AbstractJuMPScalar}
    JuMP.add_to_expression!(expression, multiplier, var)
    return
end

function _add_expression_container!(
    container::SingleOptimizationContainer,
    expr_key::ExpressionKey,
    ::Type{T},
    axs...;
    sparse=false,
) where {T <: JuMP.AbstractJuMPScalar}
    if sparse
        expr_container = sparse_container_spec(T, axs...)
    else
        expr_container = container_spec(T, axs...)
    end
    remove_undef!(expr_container)
    _assign_container!(container.expressions, expr_key, expr_container)
    return expr_container
end

function add_expression_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    axs...;
    sparse=false,
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    expr_key = ExpressionKey(T, U, meta)
    return _add_expression_container!(container, expr_key, GAE, axs...; sparse=sparse)
end

function get_expression_keys(container::SingleOptimizationContainer)
    return collect(keys(container.expressions))
end

function get_expression(container::SingleOptimizationContainer, key::ExpressionKey)
    var = get(container.expressions, key, nothing)
    if var === nothing
        throw(
            IS.InvalidValue(
                "constraint $key is not stored. $(collect(keys(container.expressions)))",
            ),
        )
    end

    return var
end

function get_expression(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_expression(container, ExpressionKey(T, U, meta))
end

function get_expression(
    container::SingleOptimizationContainer,
    ::T,
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType}
    return get_expression(container, ExpressionKey(T, meta))
end

##################################### Objective Function Container #################################
function update_objective_function!(container::SingleOptimizationContainer)
    JuMP.@objective(
        get_jump_model(container),
        get_sense(container.objective_function),
        get_objective_expression(container.objective_function)
    )
    return
end

function add_to_objective_operations_expression!(
    container::SingleOptimizationContainer,
    cost_expr::T,
) where {T <: JuMP.AbstractJuMPScalar}
    T_cf = typeof(container.objective_function.operation_terms)
    if T_cf <: JuMP.GenericAffExpr && T <: JuMP.GenericQuadExpr
        container.objective_function.operation_terms += cost_expr
    else
        JuMP.add_to_expression!(container.objective_function.operation_terms, cost_expr)
    end
    return
end

function add_to_objective_investment_expression!(
    container::SingleOptimizationContainer,
    cost_expr::T,
) where {T <: JuMP.AbstractJuMPScalar}
    T_cf = typeof(container.objective_function.capital_terms)
    if T_cf <: JuMP.GenericAffExpr && T <: JuMP.GenericQuadExpr
        container.objective_function.capital_terms += cost_expr
    else
        JuMP.add_to_expression!(container.objective_function.capital_terms, cost_expr)
    end
    return
end

##### Initialize Expressions #####

function _make_container_array(ax...)
    return remove_undef!(DenseAxisArray{GAE}(undef, ax...))
end

function _make_system_expressions!(
    container::SingleOptimizationContainer,
    ::Type{SingleRegionBalanceModel},
)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    container.expressions = Dict(
        ExpressionKey(EnergyBalance, PSIP.Portfolio) =>
            _make_container_array([SINGLE_REGION], time_steps),
        ExpressionKey(FeasibilitySurplus, PSIP.Portfolio) =>
            _make_container_array([SINGLE_REGION], time_steps),
    )
    return
end

function _make_system_expressions!(
    container::SingleOptimizationContainer,
    ::Type{MultiRegionBalanceModel},
    port::PSIP.Portfolio,
)
    regions = PSIP.get_name.(PSIP.get_regions(PSIP.Zone, port))
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    container.expressions = Dict(
        ExpressionKey(EnergyBalance, PSIP.Portfolio) =>
            _make_container_array(regions, time_steps),
        ExpressionKey(FeasibilitySurplus, PSIP.Portfolio) =>
            _make_container_array(regions, time_steps),
    )
    return
end

function _make_system_expressions!(
    container::SingleOptimizationContainer,
    ::Type{NodalBalanceModel},
    port::PSIP.Portfolio,
)
    nodes = PSIP.get_name.(PSIP.get_regions(PSIP.Node, port))
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    container.expressions = Dict(
        ExpressionKey(EnergyBalance, PSIP.Portfolio) =>
            _make_container_array(nodes, time_steps),
        ExpressionKey(FeasibilitySurplus, PSIP.Portfolio) =>
            _make_container_array(nodes, time_steps),
    )
    return
end

function initialize_system_expressions!(
    container::SingleOptimizationContainer,
    transport_model::TransportModel{T},
    port::PSIP.Portfolio,
) where {T <: SingleRegionBalanceModel}
    _make_system_expressions!(container, T)
    return
end

function initialize_system_expressions!(
    container::SingleOptimizationContainer,
    transport_model::TransportModel{T},
    port::PSIP.Portfolio,
) where {T <: MultiRegionBalanceModel}
    _make_system_expressions!(container, T, port)
    return
end

function initialize_system_expressions!(
    container::SingleOptimizationContainer,
    transport_model::TransportModel{T},
    port::PSIP.Portfolio,
) where {T <: NodalBalanceModel}
    _make_system_expressions!(container, T, port)
    return
end

################################### Aux Variables and Duals ############################

function calculate_aux_variables!(
    container::SingleOptimizationContainer,
    port::PSIP.Portfolio,
)
    aux_vars = get_aux_variables(container)
    for key in keys(aux_vars)
        calculate_aux_variable_value!(container, key, port)
    end
    return RunStatus.SUCCESSFULLY_FINALIZED
end

function _calculate_dual_variables_discrete_model!(
    container::SingleOptimizationContainer,
    ::PSIP.Portfolio,
)
    return _process_duals(container, container.settings.optimizer)
end

function calculate_dual_variables!(
    container::SingleOptimizationContainer,
    port::PSIP.Portfolio,
    is_milp::Bool,
)
    isempty(get_duals(container)) && return RunStatus.SUCCESSFULLY_FINALIZED
    if is_milp
        status = _calculate_dual_variables_discrete_model!(container, port)
    else
        status = _calculate_dual_variables_continous_model!(container, port)
    end
    return
end

##### Build Models #######

function construct_devices!(
    container::SingleOptimizationContainer,
    template::InvestmentModelTemplate,
    port::PSIP.Portfolio,
)
    device_models_dict = get_device_models(template)
    if isempty(device_models_dict) || isnothing(PSIP.get_base_system(port))
        return
    end

    base_system = PSIP.get_base_system(port)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    jump_model = get_jump_model(container)
    energy_balance_expr = get_expression(container, EnergyBalance(), PSIP.Portfolio)

    # Process each device type configured in device_models
    for (component_type, operation_formulation) in device_models_dict
        device_components = PSY.get_components(component_type, base_system)
        device_list = collect(device_components)

        if isempty(device_list)
            continue
        end

        # Handle generators: create dispatch variables and add to supply
        if component_type <: PSY.Generator
            tech_model_str = string(operation_formulation)
            device_names = PSY.get_name.(device_list)

            # Register variables in container using extended add_variable_container! for PSY types
            dispatch_vars = add_variable_container!(
                container,
                ActivePowerVariable(),
                component_type,
                device_names,
                time_steps,
                meta=tech_model_str,
            )

            # Create JuMP variables and set bounds using PSI2 pattern
            for device in device_list
                name = PSY.get_name(device)
                ub = PSY.get_max_active_power(device)

                for t in time_steps
                    # Create variable with proper naming pattern
                    type_name = split(string(component_type), '.')[end]
                    base_var_name = "$(ActivePowerVariable)_$(type_name)_{$(name), $(t)}"
                    dispatch_vars[name, t] = JuMP.@variable(
                        jump_model,
                        base_name=base_var_name,
                    )
                    JuMP.set_lower_bound(dispatch_vars[name, t], 0.0)
                    JuMP.set_upper_bound(dispatch_vars[name, t], ub)
                end
            end

            # Add device dispatch to energy balance expression
            for t in time_steps
                for device in device_list
                    name = PSY.get_name(device)
                    JuMP.add_to_expression!(energy_balance_expr[SINGLE_REGION, t], dispatch_vars[name, t])
                end
            end

            # Apply capacity factor constraints for renewable devices
            if component_type <: PSY.RenewableDispatch
                _add_renewable_dispatch_constraints!(
                    container,
                    jump_model,
                    dispatch_vars,
                    device_list,
                    time_mapping,
                    component_type,
                    tech_model_str,
                )
            end

        # Handle loads: fixed demand
        elseif component_type <: PSY.PowerLoad
            for device in device_list
                device_name = PSY.get_name(device)
                fixed_demand = PSY.get_max_active_power(device)

                for t in time_steps
                    JuMP.add_to_expression!(energy_balance_expr[SINGLE_REGION, t], -fixed_demand)
                end
            end
        end
    end

    return
end

function _add_renewable_dispatch_constraints!(
    container::SingleOptimizationContainer,
    jump_model::JuMP.Model,
    dispatch_vars::AbstractArray,
    devices::Vector,
    time_mapping::TimeMapping,
    component_type::Type,
    tech_model_str::String,
)
    time_stamps = get_time_stamps(time_mapping)
    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    device_names = PSY.get_name.(devices)

    # Register constraints in container
    con_ub = add_constraints_container!(
        container,
        ActivePowerLimitsConstraint(),
        component_type,
        device_names,
        get_time_steps(time_mapping),
        meta=tech_model_str,
    )

    for device in devices
        name = PSY.get_name(device)
        max_power = PSY.get_max_active_power(device)

        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            first_t = first(time_slices)
            first_ts = time_stamps[first_t]

            # Retrieve time series from base_system device
            # Time series stores capacity factors (0.0-1.0), scaled by device max_power
            ts_data = nothing
            ts_name = "max_active_power"

            try
                # Get raw time series (capacity factors)
                ts = IS.get_time_series(
                    IS.SingleTimeSeries,
                    device,
                    ts_name,
                )
                ts_data = TimeSeries.values(ts.data)
            catch
                # Time series not found - constraint will use max power only
            end

            # Apply capacity constraints
            for (ix, t) in enumerate(time_slices)
                if ts_data !== nothing && length(ts_data) >= ix
                    # Apply constraint: dispatch <= capacity_factor * max_power
                    con_ub[name, t] = JuMP.@constraint(
                        jump_model,
                        dispatch_vars[name, t] <= ts_data[ix] * max_power,
                    )
                else
                    # Fallback: constraint with max power only
                    con_ub[name, t] = JuMP.@constraint(
                        jump_model,
                        dispatch_vars[name, t] <= max_power,
                    )
                end
            end
        end
    end

    return
end

function build_model!(
    container::SingleOptimizationContainer,
    template::InvestmentModelTemplate,
    port::PSIP.Portfolio,
)
    transport_model = get_transport_model(template)
    initialize_system_expressions!(container, transport_model, port)

    # Process base_system devices BEFORE constructing technologies
    # so device variables are available when energy balance constraints are built
    construct_devices!(container, template, port)

    tech_names = collect(values(template.technology_models))

    # Check for duplicate technologies
    flattened_list = collect(Iterators.flatten(tech_names))
    if !allunique(flattened_list)
        error("Multiple technology models defined for the same technology")
    end

    # Technology Maps #
    type_capital_map, type_operation_map, type_feasibility_map =
        get_type_formulation_to_names_map(template.technology_models, port)
    names_to_model_map = names_to_technology_model_map(template.technology_models)
    # Branch Technology Maps #
    br_type_capital_map, br_type_operation_map, br_type_feasibility_map =
        get_type_formulation_to_names_map(template.branch_models, port)
    br_names_to_model_map = names_to_technology_model_map(template.branch_models)

    # Only build the feasibility model if there are feasibility timesteps
    if is_feasibility_empty(get_time_mapping(container))
        models = [template.capital_model, template.operation_model]
        tech_maps = [type_capital_map, type_operation_map]
        br_maps = [br_type_capital_map, br_type_operation_map]
    else
        models =
            [template.capital_model, template.operation_model, template.feasibility_model]
        tech_maps = [type_capital_map, type_operation_map, type_feasibility_map]
        br_maps = [br_type_capital_map, br_type_operation_map, br_type_feasibility_map]
    end

    ########################
    #### Argument Stage ####
    ########################

    # Order is required
    # Arguments for Technologies #
    for (ix, type_map) in enumerate(tech_maps)
        for (tuple, name_list) in type_map
            tech_type, tech_formulation = tuple
            tech_model_vector =
                names_to_technology_model_vector(names_to_model_map, name_list)
            construct_technologies!(
                container,
                port,
                name_list,
                ArgumentConstructStage(),
                models[ix],
                tech_type,
                tech_formulation,
                transport_model,
                tech_model_vector,
            )
        end
    end

    # TODO:
    # Requirements Arguments HERE
    #=
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Requirements" begin
        construct_requirements!(
            container,
            sys,
            ArgumentConstructStage(),
            get_service_models(template),
            get_device_models(template),
            transmission_model,
        )
    end
    =#

    # Branches Model Arguments #
    for (ix, type_map) in enumerate(br_maps)
        for (tuple, name_list) in type_map
            tech_type, tech_formulation = tuple
            tech_model_vector =
                names_to_technology_model_vector(br_names_to_model_map, name_list)
            construct_technologies!(
                container,
                port,
                name_list,
                ArgumentConstructStage(),
                models[ix],
                tech_type,
                tech_formulation,
                transport_model,
                tech_model_vector,
            )
        end
    end

    # Constructor for transport model, adds EnergyBalanceConstraint
    construct_transport!(container, port, transport_model)

    ########################
    ##### Model Stage ######
    ########################

    # Model for Technologies #
    for (ix, type_map) in enumerate(tech_maps)
        for (tuple, name_list) in type_map
            tech_type, tech_formulation = tuple
            tech_model_vector =
                names_to_technology_model_vector(names_to_model_map, name_list)
            construct_technologies!(
                container,
                port,
                name_list,
                ModelConstructStage(),
                models[ix],
                tech_type,
                tech_formulation,
                transport_model,
                tech_model_vector,
            )
        end
    end

    # TODO:
    # Requirements Model HERE
    #=
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Requirements" begin
        construct_requirements!(
            container,
            sys,
            ArgumentConstructStage(),
            get_service_models(template),
            get_device_models(template),
            transmission_model,
        )
    end
    =#

    # Branches Model Arguments #
    for (ix, type_map) in enumerate(br_maps)
        for (tuple, name_list) in type_map
            tech_type, tech_formulation = tuple
            tech_model_vector =
                names_to_technology_model_vector(br_names_to_model_map, name_list)
            construct_technologies!(
                container,
                port,
                name_list,
                ModelConstructStage(),
                models[ix],
                tech_type,
                tech_formulation,
                transport_model,
                tech_model_vector,
            )
        end
    end

    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Objective" begin
        @debug "Building Objective" _group = LOG_GROUP_OPTIMIZATION_CONTAINER
        update_objective_function!(container)
    end
    @debug "Total operation count $(get_jump_model(container).operator_counter)" _group =
        LOG_GROUP_OPTIMIZATION_CONTAINER

    check_optimization_container(container)

    peak_demand = get_peak_demand(port)
    system = PSIP.get_base_system(port)
    capacity_credits = get_capacity_credits(port, system)
    reserve_margin = something(port.metadata.reserve_margin, 0.0)
    @debug "Adding capacity adequacy constraint with reserve margin $reserve_margin, peak demand $peak_demand, capacity credits $capacity_credits" _group = LOG_GROUP_OPTIMIZATION_CONTAINER

    add_capacity_adequacy_constraint!(container, port, peak_demand, reserve_margin, capacity_credits)


    return
end

"""
Default solve method for OptimizationContainer
"""
function solve_model!(container::SingleOptimizationContainer, port::PSIP.Portfolio)
    optimizer_stats = get_optimizer_stats(container)

    jump_model = get_jump_model(container)

    model_status = MOI.NO_SOLUTION::MOI.ResultStatusCode
    conflict_status = MOI.COMPUTE_CONFLICT_NOT_CALLED

    try_count = 0
    while model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
        _,
        optimizer_stats.timed_solve_time,
        optimizer_stats.solve_bytes_alloc,
        optimizer_stats.sec_in_gc = @timed JuMP.optimize!(jump_model)
        model_status = JuMP.primal_status(jump_model)

        if model_status != MOI.FEASIBLE_POINT::MOI.ResultStatusCode
            if get_calculate_conflict(get_settings(container))
                @warn "Optimizer returned $model_status computing conflict"
                conflict_status = compute_conflict!(container)
                if conflict_status == MOI.CONFLICT_FOUND
                    return RunStatus.FAILED
                end
            else
                @warn "Optimizer returned $model_status trying optimize! again"
            end

            try_count += 1
            if try_count > MAX_OPTIMIZE_TRIES
                @error "Optimizer returned $model_status after $MAX_OPTIMIZE_TRIES optimize! attempts"
                return RunStatus.FAILED
            end
        end
    end

    _, optimizer_stats.timed_calculate_aux_variables =
        @timed calculate_aux_variables!(container, port)

    # Needs to be called here to avoid issues when getting duals from MILPs
    write_optimizer_stats!(container)

    _, optimizer_stats.timed_calculate_dual_variables =
        @timed calculate_dual_variables!(container, port, is_milp(container))

    status = RunStatus.SUCCESSFULLY_FINALIZED

    return status
end

function write_optimizer_stats!(container::SingleOptimizationContainer)
    write_optimizer_stats!(get_optimizer_stats(container), get_jump_model(container))
    return
end

"""
Exports the OpModel JuMP object in MathOptFormat
"""
function serialize_optimization_model(
    container::SingleOptimizationContainer,
    save_path::String,
)
    serialize_jump_optimization_model(get_jump_model(container), save_path)
    return
end

"""
Each Tuple corresponds to (con_name, internal_index, moi_index)
"""
function get_all_variable_index(container::SingleOptimizationContainer)
    var_keys = get_all_variable_keys(container)
    return [IS.Optimization.encode_key(v) for v in var_keys]
end

# Probably a more efficiency way of doing this
function get_all_variable_keys(container::SingleOptimizationContainer)
    var_index = Vector{VariableKey}()
    for (key, value) in get_variables(container)
        push!(var_index, key)
    end
    return var_index
end

function check_duplicate_names(
    names::Vector{String},
    container::SingleOptimizationContainer,
    variable_type::T,
    tech_type::Type{D},
    meta=ISOPT.CONTAINER_KEY_EMPTY_META,
) where {T <: ISOPT.VariableType, D <: PSIP.Technology}
    duplicate = false
    n = ""
    try
        variable = get_variable(container, variable_type, tech_type)
        ax = axes(variable)
        for name in names
            if (name * meta in ax[1])
                duplicate = true
                n = name
            end
        end
    catch
        true
    end

    if duplicate
        throw(ArgumentError("$n is already being used with another technology model"))
    end
end

function serialize_metadata!(container::SingleOptimizationContainer, output_dir::String)
    for key in Iterators.flatten((
        keys(container.constraints),
        keys(container.duals),
        keys(container.variables),
        keys(container.aux_variables),
        keys(container.expressions),
    ))
        encoded_key = encode_key_as_string(key)
        if IS.Optimization.has_container_key(container.metadata, encoded_key)
            # Constraints and Duals can store the same key.
            IS.@assert_op key ==
                          IS.Optimization.get_container_key(container.metadata, encoded_key)
        end
        IS.Optimization.add_container_key!(container.metadata, encoded_key, key)
    end

    filename = IS.Optimization._make_metadata_filename(output_dir)
    # TODO: Fix Serialization Metadata
    #Serialization.serialize(filename, container.metadata)
end
