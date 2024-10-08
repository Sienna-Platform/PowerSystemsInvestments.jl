Base.@kwdef mutable struct SingleOptimizationContainer <:
                           ISOPT.AbstractOptimizationContainer
    JuMPmodel::JuMP.Model
    time_steps::UnitRange{Int}
    time_steps_investments::UnitRange{Int}
    settings::Settings
    settings_copy::Settings
    variables::Dict{ISOPT.VariableKey, AbstractArray}
    aux_variables::Dict{ISOPT.AuxVarKey, AbstractArray}
    duals::Dict{ISOPT.ConstraintKey, AbstractArray}
    constraints::Dict{ISOPT.ConstraintKey, AbstractArray}
    objective_function::ObjectiveFunction
    expressions::Dict{ISOPT.ExpressionKey, AbstractArray}
    parameters::Dict{ISOPT.ParameterKey, ParameterContainer}
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
        1:1,
        1:1,
        settings,
        copy_for_serialization(settings),
        Dict{VariableKey, AbstractArray}(),
        Dict{AuxVarKey, AbstractArray}(),
        Dict{ConstraintKey, AbstractArray}(),
        Dict{ConstraintKey, AbstractArray}(),
        ObjectiveFunction(),
        Dict{ExpressionKey, AbstractArray}(),
        Dict{ParameterKey, ParameterContainer}(),
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
get_parameters(container::SingleOptimizationContainer) = container.parameters
get_resolution(container::SingleOptimizationContainer) = get_resolution(container.settings)
get_settings(container::SingleOptimizationContainer) = container.settings
get_time_steps(container::SingleOptimizationContainer) = container.time_steps
get_time_steps_investments(container::SingleOptimizationContainer) =
    container.time_steps_investments
get_variables(container::SingleOptimizationContainer) = container.variables

set_initial_conditions_data!(container::SingleOptimizationContainer, data) =
    container.initial_conditions_data = data
get_objective_expression(container::SingleOptimizationContainer) =
    container.objective_function
is_synchronized(container::SingleOptimizationContainer) =
    container.objective_function.synchronized
set_time_steps!(container::SingleOptimizationContainer, time_steps::UnitRange{Int64}) =
    container.time_steps = time_steps
set_time_steps_investments!(
    container::SingleOptimizationContainer,
    time_steps::UnitRange{Int64},
) = container.time_steps_investments = time_steps

get_aux_variables(container::SingleOptimizationContainer) = container.aux_variables
get_base_power(container::SingleOptimizationContainer) = container.base_power
get_constraints(container::SingleOptimizationContainer) = container.constraints

function _assign_container!(container::Dict, key::OptimizationContainerKey, value)
    if haskey(container, key)
        @error "$(IS.Optimization.encode_key(key)) is already stored" sort!(
            IS.Optimization.encode_key.(keys(container)),
        )
        throw(IS.InvalidValue("$key is already stored"))
    end
    container[key] = value
    #@debug "Added container entry $(typeof(key)) $(IS.Optimization.encode_key(key))" _group =
    #    LOG_GROUP_OPTIMZATION_CONTAINER
    return
end

function has_container_key(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = ExpressionKey(T, U, meta)
    return haskey(container.expressions, key)
end

function has_container_key(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: VariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = VariableKey(T, U, meta)
    return haskey(container.variables, key)
end

function has_container_key(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: AuxVariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = AuxVarKey(T, U, meta)
    return haskey(container.aux_variables, key)
end

function has_container_key(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = ConstraintKey(T, U, meta)
    return haskey(container.constraints, key)
end

function has_container_key(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ParameterType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = ParameterKey(T, U, meta)
    return haskey(container.parameters, key)
end

#=
function has_container_key(
    container:SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    meta = IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: InitialConditionType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    key = InitialConditionKey(T, U, meta)
    return haskey(container.initial_conditions, key)
end
=#

####################################### Variable Container #################################
function _add_variable_container!(
    container::SingleOptimizationContainer,
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
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    axs...;
    sparse=false,
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
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
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: SparseVariableType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    var_key = VariableKey(T, U, meta)
    _assign_container!(container.variables, var_key, _get_pwl_variables_container())
    return container.variables[var_key]
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
    meta::String=IS.Optimization.CONTAINER_KEY_EMPTY_META,
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
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
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
    meta::String=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ConstraintType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_constraint(container, ConstraintKey(T, U, meta))
end

#=
function read_duals(container::SingleOptimizationContainer)
    return Dict(k => to_dataframe(jump_value.(v), k) for (k, v) in get_duals(container))
end
=#

##################################### Parameter Container ##################################
function _add_param_container!(
    container::SingleOptimizationContainer,
    key::ParameterKey{T, U},
    attribute::VariableValueAttributes{<:OptimizationContainerKey},
    param_type::DataType,
    axs...;
    sparse=false,
) where {T <: VariableValueParameter, U <: PSY.Component}
    if sparse
        param_array = sparse_container_spec(param_type, axs...)
        multiplier_array = sparse_container_spec(Float64, axs...)
    else
        param_array = DenseAxisArray{param_type}(undef, axs...)
        multiplier_array = fill!(DenseAxisArray{Float64}(undef, axs...), NaN)
    end
    param_container = ParameterContainer(attribute, param_array, multiplier_array)
    _assign_container!(container.parameters, key, param_container)
    return param_container
end

function _add_param_container!(
    container::SingleOptimizationContainer,
    key::ParameterKey{T, U},
    attribute::VariableValueAttributes{<:OptimizationContainerKey},
    axs...;
    sparse=false,
) where {T <: VariableValueParameter, U <: PSY.Component}
    if built_for_recurrent_solves(container) && !get_rebuild_model(get_settings(container))
        param_type = JuMP.VariableRef
    else
        param_type = Float64
    end
    return _add_param_container!(
        container,
        key,
        attribute,
        param_type,
        axs...;
        sparse=sparse,
    )
end

function _add_param_container!(
    container::SingleOptimizationContainer,
    key::ParameterKey{T, U},
    attribute::TimeSeriesAttributes{V},
    param_axs,
    multiplier_axs,
    time_steps;
    sparse=false,
) where {T <: TimeSeriesParameter, U <: PSY.Component, V <: PSY.TimeSeriesData}
    if built_for_recurrent_solves(container) && !get_rebuild_model(get_settings(container))
        param_type = JuMP.VariableRef
    else
        param_type = Float64
    end

    if sparse
        param_array = sparse_container_spec(param_type, param_axs, time_steps)
        multiplier_array = sparse_container_spec(Float64, multiplier_axs, time_steps)
    else
        param_array = DenseAxisArray{param_type}(undef, param_axs, time_steps)
        multiplier_array =
            fill!(DenseAxisArray{Float64}(undef, multiplier_axs, time_steps), NaN)
    end
    param_container = ParameterContainer(attribute, param_array, multiplier_array)
    _assign_container!(container.parameters, key, param_container)
    return param_container
end

function _add_param_container!(
    container::SingleOptimizationContainer,
    key::ParameterKey{T, U},
    attributes::CostFunctionAttributes{R},
    axs...;
    sparse=false,
) where {R, T <: ObjectiveFunctionParameter, U <: PSY.Component}
    if sparse
        param_array = sparse_container_spec(R, axs...)
        multiplier_array = sparse_container_spec(Float64, axs...)
    else
        param_array = DenseAxisArray{R}(undef, axs...)
        multiplier_array = fill!(DenseAxisArray{Float64}(undef, axs...), NaN)
    end
    param_container = ParameterContainer(attributes, param_array, multiplier_array)
    _assign_container!(container.parameters, key, param_container)
    return param_container
end

function add_param_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    ::Type{V},
    name::String,
    param_axs,
    multiplier_axs,
    time_steps;
    sparse=false,
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: TimeSeriesParameter, U <: PSY.Component, V <: PSY.TimeSeriesData}
    param_key = ParameterKey(T, U, meta)
    if isabstracttype(V)
        error("$V can't be abstract: $param_key")
    end
    attributes = TimeSeriesAttributes(V, name)
    return _add_param_container!(
        container,
        param_key,
        attributes,
        param_axs,
        multiplier_axs,
        time_steps;
        sparse=sparse,
    )
end

function add_param_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    variable_type::Type{W},
    sos_variable::SOSStatusVariable=NO_VARIABLE,
    uses_compact_power::Bool=false,
    data_type::DataType=Float64,
    axs...;
    sparse=false,
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ObjectiveFunctionParameter, U <: PSY.Component, W <: VariableType}
    param_key = ParameterKey(T, U, meta)
    attributes =
        CostFunctionAttributes{data_type}(variable_type, sos_variable, uses_compact_power)
    return _add_param_container!(container, param_key, attributes, axs...; sparse=sparse)
end

function add_param_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    source_key::V,
    axs...;
    sparse=false,
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: VariableValueParameter, U <: PSY.Component, V <: OptimizationContainerKey}
    param_key = ParameterKey(T, U, meta)
    attributes = VariableValueAttributes(source_key)
    return _add_param_container!(container, param_key, attributes, axs...; sparse=sparse)
end

# FixValue parameters are created using Float64 since we employ JuMP.fix to fix the downstream
# variables.

function add_param_container!(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    source_key::V,
    axs...;
    sparse=false,
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: FixValueParameter, U <: PSY.Component, V <: OptimizationContainerKey}
    if meta == IS.Optimization.CONTAINER_KEY_EMPTY_META
        error("$T parameters require passing the VariableType to the meta field")
    end
    param_key = ParameterKey(T, U, meta)
    attributes = VariableValueAttributes(source_key)
    return _add_param_container!(
        container,
        param_key,
        attributes,
        Float64,
        axs...;
        sparse=sparse,
    )
end

function get_parameter_keys(container::SingleOptimizationContainer)
    return collect(keys(container.parameters))
end

function get_parameter(container::SingleOptimizationContainer, key::ParameterKey)
    param_container = get(container.parameters, key, nothing)
    if param_container === nothing
        name = IS.Optimization.encode_key(key)
        throw(
            IS.InvalidValue(
                "parameter $name is not stored. $(collect(keys(container.parameters)))",
            ),
        )
    end
    return param_container
end

function get_parameter(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ParameterType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_parameter(container, ParameterKey(T, U, meta))
end

function get_parameter_array(container::SingleOptimizationContainer, key)
    return get_parameter_array(get_parameter(container, key))
end

function get_parameter_array(
    container::SingleOptimizationContainer,
    key::ParameterKey{T, U},
) where {T <: ParameterType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_parameter_array(get_parameter(container, key))
end

function get_parameter_multiplier_array(
    container::SingleOptimizationContainer,
    key::ParameterKey{T, U},
) where {T <: ParameterType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_multiplier_array(get_parameter(container, key))
end

function get_parameter_attributes(
    container::SingleOptimizationContainer,
    key::ParameterKey{T, U},
) where {T <: ParameterType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_attributes(get_parameter(container, key))
end

function get_parameter_array(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ParameterType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_parameter_array(container, ParameterKey(T, U, meta))
end

function get_parameter_multiplier_array(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ParameterType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_multiplier_array(get_parameter(container, ParameterKey(T, U, meta)))
end

function get_parameter_attributes(
    container::SingleOptimizationContainer,
    ::T,
    ::Type{U},
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ParameterType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_attributes(get_parameter(container, ParameterKey(T, U, meta)))
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
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
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
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
) where {T <: ExpressionType, U <: Union{PSIP.Technology, PSIP.Portfolio}}
    return get_expression(container, ExpressionKey(T, U, meta))
end

function get_expression(
    container::SingleOptimizationContainer,
    ::T,
    meta=IS.Optimization.CONTAINER_KEY_EMPTY_META,
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

function build_model!(
    container::SingleOptimizationContainer,
    template::InvestmentModelTemplate,
    port::PSIP.Portfolio,
)
    transmission = get_network_formulation(template)
    transmission_model = get_network_model(template)
    initialize_system_expressions!(
        container,
        get_network_model(template),
        transmission_model.subnetworks,
        sys,
        transmission_model.radial_network_reduction.bus_reduction_map,
    )

    # Order is required
    for device_model in values(template.devices)
        @debug "Building Arguments for $(get_component_type(device_model)) with $(get_formulation(device_model)) formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(get_component_type(device_model))" begin
            if validate_available_devices(device_model, sys)
                construct_device!(
                    container,
                    sys,
                    ArgumentConstructStage(),
                    device_model,
                    transmission_model,
                )
            end
            @debug "Problem size:" get_problem_size(container) _group =
                LOG_GROUP_OPTIMIZATION_CONTAINER
        end
    end

    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Services" begin
        construct_services!(
            container,
            sys,
            ArgumentConstructStage(),
            get_service_models(template),
            get_device_models(template),
            transmission_model,
        )
    end

    for branch_model in values(template.branches)
        @debug "Building Arguments for $(get_component_type(branch_model)) with $(get_formulation(branch_model)) formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(get_component_type(branch_model))" begin
            if validate_available_devices(branch_model, sys)
                construct_device!(
                    container,
                    sys,
                    ArgumentConstructStage(),
                    branch_model,
                    transmission_model,
                )
            end
            @debug "Problem size:" get_problem_size(container) _group =
                LOG_GROUP_OPTIMIZATION_CONTAINER
        end
    end

    for device_model in values(template.devices)
        @debug "Building Model for $(get_component_type(device_model)) with $(get_formulation(device_model)) formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(get_component_type(device_model))" begin
            if validate_available_devices(device_model, sys)
                construct_device!(
                    container,
                    sys,
                    ModelConstructStage(),
                    device_model,
                    transmission_model,
                )
            end
            @debug "Problem size:" get_problem_size(container) _group =
                LOG_GROUP_OPTIMIZATION_CONTAINER
        end
    end

    # This function should be called after construct_device ModelConstructStage
    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(transmission)" begin
        @debug "Building $(transmission) network formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        construct_network!(container, sys, transmission_model, template)
        @debug "Problem size:" get_problem_size(container) _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
    end

    for branch_model in values(template.branches)
        @debug "Building Model for $(get_component_type(branch_model)) with $(get_formulation(branch_model)) formulation" _group =
            LOG_GROUP_OPTIMIZATION_CONTAINER
        TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "$(get_component_type(branch_model))" begin
            if validate_available_devices(branch_model, sys)
                construct_device!(
                    container,
                    sys,
                    ModelConstructStage(),
                    branch_model,
                    transmission_model,
                )
            end
            @debug "Problem size:" get_problem_size(container) _group =
                LOG_GROUP_OPTIMIZATION_CONTAINER
        end
    end

    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Services" begin
        construct_services!(
            container,
            sys,
            ModelConstructStage(),
            get_service_models(template),
            get_device_models(template),
            transmission_model,
        )
    end

    TimerOutputs.@timeit BUILD_PROBLEMS_TIMER "Objective" begin
        @debug "Building Objective" _group = LOG_GROUP_OPTIMIZATION_CONTAINER
        update_objective_function!(container)
    end
    @debug "Total operation count $(PSI.get_jump_model(container).operator_counter)" _group =
        LOG_GROUP_OPTIMIZATION_CONTAINER

    check_optimization_container(container)
    return
end
