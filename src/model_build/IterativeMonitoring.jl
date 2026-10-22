_check_monitoring_transport(::TransportModel{NodalPTDFModel}) = nothing
_check_monitoring_transport(::TransportModel{T}) where {T} =
    error("IterativeMonitoring requires the NodalPTDFModel transport model, not $T")

function build_impl!(model::InvestmentModel{IterativeMonitoring})
    transport_model = get_transport_model(get_template(model))
    _check_monitoring_transport(transport_model)
    # Without a list of monitored corridors, the first solve limits none
    get!(transport_model.attributes, "monitored", String[])
    build_single_instance!(model)
    return
end

function solve_impl!(model::InvestmentModel{IterativeMonitoring})
    container = get_optimization_container(model)
    portfolio = get_portfolio(model)
    transport_model = get_transport_model(get_template(model))
    network = get_network_data(transport_model)
    attributes = transport_model.attributes
    max_iterations = get(attributes, "max_iterations", 20)
    tolerance = get(attributes, "overload_tolerance", 1e-4)
    threshold = get(attributes, "add_threshold", 1.0)
    log = DataFrames.DataFrame(;
        iteration=Int[],
        monitored=Int[],
        added=Int[],
        objective=Float64[],
        solve_time=Float64[],
        max_loading=Float64[],
        overloaded=Int[],
    )
    loading = Dict{String, Tuple{Float64, Float64}}()
    for iteration in 0:max_iterations
        status = solve_model!(container, portfolio)
        set_run_status!(model, status)
        status == RunStatus.SUCCESSFULLY_FINALIZED || _solve_failed(model)
        calculate_network_values!(container, transport_model, portfolio)
        loading = _corridor_loading(container, network)
        overloaded = [name for (name, (ratio, _)) in loading if ratio > 1 + tolerance]
        new_overloads = setdiff(overloaded, network.monitored)
        # Once some unmonitored corridors are overloaded, those loaded above the threshold are
        # added with them
        added =
            isempty(new_overloads) ? String[] :
            sort!(
                union(
                    new_overloads,
                    [
                        name for (name, (ratio, _)) in loading if
                        ratio > threshold && !(name in network.monitored)
                    ],
                ),
            )
        push!(
            log,
            (
                iteration,
                length(network.monitored),
                length(added),
                JuMP.objective_value(get_jump_model(container)),
                get_optimizer_stats(container).timed_solve_time,
                maximum(first, values(loading); init=0.0),
                length(overloaded),
            ),
        )
        @info "Monitoring iteration $iteration: $(length(network.monitored)) corridors monitored, objective $(last(log.objective)), solve $(round(last(log.solve_time); digits=1)) s, $(length(overloaded)) overloaded, $(length(added)) added"
        isempty(added) && break
        if iteration == max_iterations
            @warn "Stopped after $max_iterations iterations with unmonitored corridors overloaded" corridors =
                sort!(new_overloads)
            break
        end
        _add_corridors!(container, transport_model, portfolio, added)
    end
    # With a PTDF cutoff, the limited flows of monitored corridors differ from their exact flows
    residual = [
        name for (name, (ratio, _)) in loading if
        ratio > 1 + tolerance && name in network.monitored
    ]
    if !isempty(residual)
        excess = maximum(last(loading[name]) for name in residual)
        @warn "$(length(residual)) monitored corridors are above their limits in the exact flows by up to $(round(excess; digits=3)) MW (PTDF cutoff \"tol\")" corridors =
            sort!(residual)
    end
    model.ext["monitoring_log"] = log
    return
end

# Adding rows one at a time to a model loaded in the solver costs time in proportion to the
# model, so the solver is detached, the corridors are added, and the model is loaded again in one
# copy. For an LP the previous basis is restored, so the next solve starts from it.
function _add_corridors!(
    container::SingleOptimizationContainer,
    transport_model::TransportModel,
    portfolio::PSIP.Portfolio,
    names::Vector{String},
)
    jump_model = get_jump_model(container)
    # A model in direct mode cannot be detached from its solver
    if get_direct_mode_optimizer(get_settings(container))
        add_monitored_corridors!(container, transport_model, portfolio, names)
        return
    end
    basis = is_milp(container) ? nothing : _get_basis(jump_model)
    MOI.Utilities.reset_optimizer(jump_model)
    add_monitored_corridors!(container, transport_model, portfolio, names)
    isnothing(basis) || _restore_basis!(jump_model, basis)
    return
end

_constraint_refs(jump_model::JuMP.Model) =
    JuMP.all_constraints(jump_model; include_variable_in_set_constraints=false)

function _get_basis(jump_model::JuMP.Model)
    variables = JuMP.all_variables(jump_model)
    constraints = _constraint_refs(jump_model)
    return (
        Dict(zip(variables, MOI.get.(jump_model, MOI.VariableBasisStatus(), variables))),
        Dict(
            zip(
                constraints,
                MOI.get.(jump_model, MOI.ConstraintBasisStatus(), constraints),
            ),
        ),
    )
end

# Status of a new row: the equality that sets a new flow variable is nonbasic (the variable is
# basic), and a new limit has a basic slack
_new_row_status(::MOI.EqualTo) = MOI.NONBASIC
_new_row_status(::MOI.AbstractScalarSet) = MOI.BASIC

# The basis can only be set on the solver, so the model is loaded first
function _restore_basis!(jump_model::JuMP.Model, basis)
    variable_status, constraint_status = basis
    backend = JuMP.backend(jump_model)
    MOI.Utilities.attach_optimizer(backend)
    index_map = backend.model_to_optimizer_map
    for v in JuMP.all_variables(jump_model)
        MOI.set(
            backend.optimizer,
            MOI.VariableBasisStatus(),
            index_map[JuMP.index(v)],
            get(variable_status, v, MOI.BASIC),
        )
    end
    for c in _constraint_refs(jump_model)
        status = get(constraint_status, c) do
            _new_row_status(JuMP.constraint_object(c).set)
        end
        MOI.set(
            backend.optimizer,
            MOI.ConstraintBasisStatus(),
            index_map[JuMP.index(c)],
            status,
        )
    end
    return
end

"""
Log of a model solved with [`IterativeMonitoring`](@ref): for each solve, the corridors monitored
in it, the corridors added after it, its objective and solve time, the largest exact loading of a
corridor (flow over limit), and the number of overloaded corridors.
"""
get_monitoring_log(model::InvestmentModel{IterativeMonitoring}) =
    model.ext["monitoring_log"]

"""
Names of the merged corridors whose flow is limited in the model, after its last solve when it is
solved with [`IterativeMonitoring`](@ref).
"""
get_monitored_corridors(model::InvestmentModel) =
    sort!(collect(get_network_data(get_transport_model(get_template(model))).monitored))
