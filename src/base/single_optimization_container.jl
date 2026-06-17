"""
PSI-specific methods on OptimizationContainer.

Investment-specific fields (TimeMapping, financial data) are stored in InvestmentContainerData,
accessed via the container's settings.ext dictionary.
"""

function OptimizationContainer(
    settings::IOM.Settings,
    jump_model::Union{Nothing, JuMP.Model},
)
    if jump_model !== nothing && IOM.get_direct_mode_optimizer(settings)
        throw(
            IS.ConflictingInputsError(
                "Externally provided JuMP models are not compatible with the direct model keyword argument. Use JuMP.direct_model before passing the custom model",
            ),
        )
    end

    # Create a minimal "system" object for the IOM constructor that provides get_base_power
    # Investment models always use natural units (base_power = 1.0)
    container = OptimizationContainer(
        jump_model === nothing ? JuMP.Model() : jump_model,
        1:1,
        settings,
        IOM.copy_for_serialization(settings),
        OrderedDict{VariableKey, AbstractArray}(),
        OrderedDict{AuxVarKey, AbstractArray}(),
        OrderedDict{ConstraintKey, AbstractArray}(),
        OrderedDict{ConstraintKey, AbstractArray}(),
        IOM.ObjectiveFunction(),
        OrderedDict{ExpressionKey, AbstractArray}(),
        OrderedDict{IOM.ParameterKey, IOM.ParameterContainer}(),
        IOM.PrimalValuesCache(),
        OrderedDict{IOM.InitialConditionKey, Vector{IOM.InitialCondition}}(),
        IOM.InitialConditionsData(),
        Dict{Symbol, Array}(),
        nothing,
        1.0,  # base_power = 1.0 for investment models (natural units)
        IOM.OptimizerStats(),
        false,
        OptimizationContainerMetadata(),
        PSY.SingleTimeSeries,
        IOM.AbstractPowerFlowEvaluationData[],
    )
    # Store investment-specific data
    set_investment_data!(container, InvestmentContainerData())
    return container
end

# Re-export IOM accessors that PSI uses with the same names
get_jump_model(container::OptimizationContainer) = IOM.get_jump_model(container)
get_settings(container::OptimizationContainer) = IOM.get_settings(container)
get_variables(container::OptimizationContainer) = IOM.get_variables(container)
get_aux_variables(container::OptimizationContainer) = IOM.get_aux_variables(container)
get_constraints(container::OptimizationContainer) = IOM.get_constraints(container)
get_expressions(container::OptimizationContainer) = IOM.get_expressions(container)
get_duals(container::OptimizationContainer) = IOM.get_duals(container)
get_optimizer_stats(container::OptimizationContainer) = IOM.get_optimizer_stats(container)
get_metadata(container::OptimizationContainer) = IOM.get_metadata(container)
get_initial_time(container::OptimizationContainer) = IOM.get_initial_time(container)
get_resolution(container::OptimizationContainer) = IOM.get_resolution(container)
get_time_steps(container::OptimizationContainer) = IOM.get_time_steps(container)

get_objective_expression(container::OptimizationContainer) =
    IOM.get_objective_expression(container)

function is_milp(container::OptimizationContainer)::Bool
    return IOM.is_milp(container)
end

function supports_milp(container::OptimizationContainer)
    return IOM.supports_milp(container)
end

function _finalize_jump_model!(container::OptimizationContainer, settings::IOM.Settings)
    @debug "Instantiating the JuMP model" _group = LOG_GROUP_OPTIMIZATION_CONTAINER

    if IOM.get_direct_mode_optimizer(settings)
        optimizer = () -> MOI.instantiate(IOM.get_optimizer(settings))
        container.JuMPmodel = JuMP.direct_model(optimizer())
    elseif IOM.get_optimizer(settings) === nothing
        @debug "The optimization model has no optimizer attached" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
    else
        JuMP.set_optimizer(get_jump_model(container), IOM.get_optimizer(settings))
    end

    JuMPmodel = get_jump_model(container)

    JuMP.set_string_names_on_creation(JuMPmodel, IOM.get_store_variable_names(settings))

    @debug begin
        JuMP.set_string_names_on_creation(JuMPmodel, true)
    end
    if IOM.get_optimizer_solve_log_print(settings)
        JuMP.unset_silent(JuMPmodel)
        @debug "optimizer unset to silent" _group = LOG_GROUP_OPTIMIZATION_CONTAINER
    else
        JuMP.set_silent(JuMPmodel)
        @debug "optimizer set to silent" _group = LOG_GROUP_OPTIMIZATION_CONTAINER
    end
    return
end

function init_optimization_container!(
    container::OptimizationContainer,
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

    time_map = TimeMapping(
        capital_model.investment_years,
        operation_model.representative_series,
        feasibility_model.sample_periods,
    )

    set_time_mapping!(container, time_map)
    set_operational_weights!(container, operation_model.series_weights)
    # Set Financial Data in Container from Portfolio
    set_base_year!(container, PSIP.get_base_year(portfolio))
    set_discount_rate!(container, PSIP.get_discount_rate(portfolio))
    set_inflation_rate!(container, PSIP.get_inflation_rate(portfolio))
    set_interest_rate!(container, PSIP.get_interest_rate(portfolio))

    stats = get_optimizer_stats(container)
    stats.detailed_stats = IOM.get_detailed_optimizer_stats(settings)

    _finalize_jump_model!(container, settings)
    return
end

function check_optimization_container(container::OptimizationContainer)
    container.settings_copy = IOM.copy_for_serialization(container.settings)
    return
end

function _assign_container!(container::Union{Dict, OrderedDict}, key::OptimizationContainerKey, value)
    if haskey(container, key)
        @error "$(IOM.encode_key(key)) is already stored" sort!(
            IOM.encode_key.(keys(container)),
        )
        throw(IS.InvalidValue("$key is already stored"))
    end
    container[key] = value
    return
end

####################################### Variable Container #################################
function _add_variable_container!(
    container::OptimizationContainer,
    var_key::VariableKey{T, U},
    sparse::Bool,
    axs...,
) where {T <: VariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    if sparse
        var_container = sparse_container_spec(JuMP.VariableRef, axs...)
    else
        var_container = container_spec(JuMP.VariableRef, axs...)
    end
    _assign_container!(container.variables, var_key, var_container)
    return var_container
end

function add_variable_container!(
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    axs...;
    sparse=false,
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: VariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    var_key = VariableKey(T, U, meta)
    return _add_variable_container!(container, var_key, sparse, axs...)
end

function add_variable_container!(
    container::OptimizationContainer,
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
    container::OptimizationContainer,
    ::T,
    ::Type{U};
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: SparseVariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    var_key = VariableKey(T, U, meta)
    _assign_container!(container.variables, var_key, _get_pwl_variables_container())
    return container.variables[var_key]
end

function get_variable_keys(container::OptimizationContainer)
    return collect(keys(container.variables))
end

function get_variable(container::OptimizationContainer, key::VariableKey)
    var = get(container.variables, key, nothing)
    if var === nothing
        name = IOM.encode_key(key)
        keys = IOM.encode_key.(get_variable_keys(container))
        throw(IS.InvalidValue("variable $name is not stored. $keys"))
    end
    return var
end

function get_variable(
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    meta::String=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: VariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_variable(container, VariableKey(T, U, meta))
end

##################################### Constraint Container #################################
function _add_constraints_container!(
    container::OptimizationContainer,
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
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    axs...;
    sparse=false,
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    cons_key = ConstraintKey(T, U, meta)
    return _add_constraints_container!(container, cons_key, axs...; sparse=sparse)
end

function get_constraint_keys(container::OptimizationContainer)
    return collect(keys(container.constraints))
end

function get_constraint(container::OptimizationContainer, key::ConstraintKey)
    var = get(container.constraints, key, nothing)
    if var === nothing
        name = IOM.encode_key(key)
        keys = IOM.encode_key.(get_constraint_keys(container))
        throw(IS.InvalidValue("constraint $name is not stored. $keys"))
    end

    return var
end

function get_constraint(
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    meta::String=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_constraint(container, ConstraintKey(T, U, meta))
end

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
    container::OptimizationContainer,
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
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    axs...;
    sparse=false,
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    expr_key = ExpressionKey(T, U, meta)
    return _add_expression_container!(container, expr_key, GAE, axs...; sparse=sparse)
end

function get_expression_keys(container::OptimizationContainer)
    return collect(keys(container.expressions))
end

function get_expression(container::OptimizationContainer, key::ExpressionKey)
    var = get(container.expressions, key, nothing)
    if var === nothing
        throw(
            IS.InvalidValue(
                "expression $key is not stored. $(collect(keys(container.expressions)))",
            ),
        )
    end

    return var
end

function get_expression(
    container::OptimizationContainer,
    ::T,
    ::Type{U},
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_expression(container, ExpressionKey(T, U, meta))
end

function get_expression(
    container::OptimizationContainer,
    ::T,
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType}
    return get_expression(container, ExpressionKey(T, meta))
end

##################################### has_container_key #################################
function has_container_key(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = ExpressionKey(T, U, meta)
    return haskey(container.expressions, key)
end

function has_container_key(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: VariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = VariableKey(T, U, meta)
    return haskey(container.variables, key)
end

function has_container_key(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: AuxVariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = AuxVarKey(T, U, meta)
    return haskey(container.aux_variables, key)
end

function has_container_key(
    container::OptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = ConstraintKey(T, U, meta)
    return haskey(container.constraints, key)
end

##################################### Objective Function Container #################################
function update_objective_function!(container::OptimizationContainer)
    IOM.update_objective_function!(container)
    return
end

function add_to_objective_operations_expression!(
    container::OptimizationContainer,
    cost_expr::T,
) where {T <: JuMP.AbstractJuMPScalar}
    # Map PSI operation_terms -> IOM variant_terms
    T_cf = typeof(container.objective_function.variant_terms)
    if T_cf <: JuMP.GenericAffExpr && T <: JuMP.GenericQuadExpr
        container.objective_function.variant_terms += cost_expr
    else
        JuMP.add_to_expression!(container.objective_function.variant_terms, cost_expr)
    end
    return
end

function add_to_objective_investment_expression!(
    container::OptimizationContainer,
    cost_expr::T,
) where {T <: JuMP.AbstractJuMPScalar}
    # Map PSI capital_terms -> IOM invariant_terms
    T_cf = typeof(container.objective_function.invariant_terms)
    if T_cf <: JuMP.GenericAffExpr && T <: JuMP.GenericQuadExpr
        container.objective_function.invariant_terms += cost_expr
    else
        JuMP.add_to_expression!(container.objective_function.invariant_terms, cost_expr)
    end
    return
end

##### Initialize Expressions #####

function _make_container_array(ax...)
    return remove_undef!(DenseAxisArray{GAE}(undef, ax...))
end

function _make_system_expressions!(
    container::OptimizationContainer,
    ::Type{SingleRegionBalanceModel},
)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    container.expressions = OrderedDict(
        ExpressionKey(EnergyBalance, PSIP.Portfolio) =>
            _make_container_array([SINGLE_REGION], time_steps),
        ExpressionKey(FeasibilitySurplus, PSIP.Portfolio) =>
            _make_container_array([SINGLE_REGION], time_steps),
    )
    return
end

function _make_system_expressions!(
    container::OptimizationContainer,
    ::Type{MultiRegionBalanceModel},
    port::PSIP.Portfolio,
)
    regions = PSIP.get_name.(PSIP.get_regions(PSIP.Zone, port))
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    container.expressions = OrderedDict(
        ExpressionKey(EnergyBalance, PSIP.Portfolio) =>
            _make_container_array(regions, time_steps),
        ExpressionKey(FeasibilitySurplus, PSIP.Portfolio) =>
            _make_container_array(regions, time_steps),
    )
    return
end

function _make_system_expressions!(
    container::OptimizationContainer,
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

function _make_system_expressions!(
    container::OptimizationContainer,
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
    container::OptimizationContainer,
    transport_model::TransportModel{T},
    port::PSIP.Portfolio,
) where {T <: SingleRegionBalanceModel}
    _make_system_expressions!(container, T)
    return
end

function initialize_system_expressions!(
    container::OptimizationContainer,
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
    container::OptimizationContainer,
    port::PSIP.Portfolio,
)
    aux_vars = get_aux_variables(container)
    for key in keys(aux_vars)
        calculate_aux_variable_value!(container, key, port)
    end
    return RunStatus.SUCCESSFULLY_FINALIZED
end

function _calculate_dual_variables_discrete_model!(
    container::OptimizationContainer,
    ::PSIP.Portfolio,
)
    return _process_duals(container, container.settings.optimizer)
end

function calculate_dual_variables!(
    container::OptimizationContainer,
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

function build_model!(
    container::OptimizationContainer,
    template::InvestmentModelTemplate,
    port::PSIP.Portfolio,
)
    transport_model = get_transport_model(template)
    initialize_system_expressions!(container, transport_model, port)

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
    return
end

"""
Default solve method for OptimizationContainer
"""
function solve_model!(container::OptimizationContainer, port::PSIP.Portfolio)
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
            if IOM.get_calculate_conflict(get_settings(container))
                @warn "Optimizer returned $model_status computing conflict"
                conflict_status = IOM.compute_conflict!(container)
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

function write_optimizer_stats!(container::OptimizationContainer)
    write_optimizer_stats!(get_optimizer_stats(container), get_jump_model(container))
    return
end

function compute_conflict!(container::SingleOptimizationContainer)
    jump_model = get_jump_model(container)
    settings = get_settings(container)
    JuMP.unset_silent(jump_model)
    jump_model.is_model_dirty = false
    conflict = container.infeasibility_conflict
    empty!(conflict)
    try
        JuMP.compute_conflict!(jump_model)
        conflict_status = MOI.get(jump_model, MOI.ConflictStatus())
        if conflict_status != MOI.CONFLICT_FOUND
            @error "No conflict could be found for the model. Status: $conflict_status"
            if !get_optimizer_solve_log_print(settings)
                JuMP.set_silent(jump_model)
            end
            return conflict_status
        end

        for (key, field_container) in get_constraints(container)
            conflict_indices = check_conflict_status(jump_model, field_container)
            if isempty(conflict_indices)
                @info "Conflict Index returned empty for $key"
                continue
            else
                conflict[ISOPT.encode_key(key)] = conflict_indices
            end
        end

        msg = IOBuffer()
        for (k, v) in conflict
            PrettyTables.pretty_table(msg, v; header=[k])
        end
        @error "Constraints participating in conflict basis (IIS) \n\n$(String(take!(msg)))"

        return conflict_status
    catch e
        jump_model.is_model_dirty = true
        if isa(e, MethodError)
            @info "Can't compute conflict, check that your optimizer supports conflict refining/IIS"
        else
            @error "Can't compute conflict" exception = (e, catch_backtrace())
        end
    end

    return MOI.NO_CONFLICT_EXISTS
end

"""
Exports the OpModel JuMP object in MathOptFormat
"""
function serialize_optimization_model(
    container::OptimizationContainer,
    save_path::String,
)
    serialize_jump_optimization_model(get_jump_model(container), save_path)
    return
end

"""
Each Tuple corresponds to (con_name, internal_index, moi_index)
"""
function get_all_variable_index(container::OptimizationContainer)
    var_keys = get_all_variable_keys(container)
    return [IOM.encode_key(v) for v in var_keys]
end

# Probably a more efficiency way of doing this
function get_all_variable_keys(container::OptimizationContainer)
    var_index = Vector{VariableKey}()
    for (key, value) in get_variables(container)
        push!(var_index, key)
    end
    return var_index
end

function check_duplicate_names(
    names::Vector{String},
    container::OptimizationContainer,
    variable_type::T,
    tech_type::Type{D},
    meta=IOM.CONTAINER_KEY_EMPTY_META,
) where {T <: IOM.VariableType, D <: PSIP.Technology}
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

function serialize_metadata!(container::OptimizationContainer, output_dir::String)
    for key in Iterators.flatten((
        keys(container.constraints),
        keys(container.duals),
        keys(container.variables),
        keys(container.aux_variables),
        keys(container.expressions),
    ))
        encoded_key = encode_key_as_string(key)
        if IOM.has_container_key(container.metadata, encoded_key)
            # Constraints and Duals can store the same key.
            IS.@assert_op key ==
                          IOM.get_container_key(container.metadata, encoded_key)
        end
        IOM.add_container_key!(container.metadata, encoded_key, key)
    end

    filename = IOM._make_metadata_filename(output_dir)
    # TODO: Fix Serialization Metadata
    #Serialization.serialize(filename, container.metadata)
end
