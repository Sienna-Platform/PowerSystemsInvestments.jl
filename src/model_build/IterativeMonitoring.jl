_check_monitoring_transport(::TransportModel{NodalPTDFModel}) = nothing
_check_monitoring_transport(::TransportModel{T}) where {T} =
    error("IterativeMonitoring requires the NodalPTDFModel transport model, not $T")

function build_impl!(model::InvestmentModel{IterativeMonitoring})
    transport_model = get_transport_model(get_template(model))
    _check_monitoring_transport(transport_model)
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
    jump_model = get_jump_model(container)
    milp = is_milp(container)
    # A MIP is first screened with integrality relaxed, and then with a looser gap
    undo_relax =
        milp && get(attributes, "relaxed_screening", true) ?
        JuMP.relax_integrality(jump_model) : nothing
    screening_gap = get(attributes, "screening_mip_gap", nothing)
    target_gap = nothing
    if milp && !isnothing(screening_gap)
        target_gap = JuMP.get_attribute(jump_model, MOI.RelativeGapTolerance())
        JuMP.set_attribute(jump_model, MOI.RelativeGapTolerance(), screening_gap)
    end
    # Moves to the next stage, and returns false when already at the final one
    function next_stage!()
        if !isnothing(undo_relax)
            undo_relax()
            undo_relax = nothing
        elseif !isnothing(target_gap)
            JuMP.set_attribute(jump_model, MOI.RelativeGapTolerance(), target_gap)
            target_gap = nothing
        else
            return false
        end
        return true
    end
    log = DataFrames.DataFrame(;
        stage=String[],
        iteration=Int[],
        monitored=Int[],
        added=Int[],
        objective=Float64[],
        solve_time=Float64[],
        max_loading=Float64[],
        overloaded=Int[],
    )
    loading = Dict{String, Tuple{Float64, Float64}}()
    rounds = 0
    capped = false
    for iteration in Iterators.countfrom(0)
        stage =
            !isnothing(undo_relax) ? "relaxed" :
            !isnothing(target_gap) ? "screening gap" : "final"
        status = solve_model!(container, portfolio)
        set_run_status!(model, status)
        status == RunStatus.SUCCESSFULLY_FINALIZED || _solve_failed(model)
        calculate_network_values!(container, transport_model, portfolio)
        loading = _corridor_loading(container, network)
        overloaded = [name for (name, (ratio, _)) in loading if ratio > 1 + tolerance]
        new_overloads = setdiff(overloaded, network.monitored)
        added =
            isempty(new_overloads) || capped ? String[] :
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
                stage,
                iteration,
                length(network.monitored),
                length(added),
                JuMP.objective_value(jump_model),
                get_optimizer_stats(container).timed_solve_time,
                maximum(first, values(loading); init=0.0),
                length(overloaded),
            ),
        )
        @info "Monitoring iteration $iteration" last(log)
        if capped
            isempty(new_overloads) ||
                @warn "Stopped after $max_iterations rounds with corridors overloaded" corridors =
                    sort!(new_overloads)
            break
        end
        if isempty(added)
            next_stage!() || break
            continue
        end
        if rounds == max_iterations
            # The last solve is always a final one
            capped = true
            while next_stage!()
            end
            stage == "final" || continue
            @warn "Stopped after $max_iterations rounds with corridors overloaded" corridors =
                sort!(new_overloads)
            break
        end
        _add_corridors!(container, transport_model, portfolio, added)
        rounds += 1
    end
    residual = [
        name for (name, (ratio, _)) in loading if
        ratio > 1 + tolerance && name in network.monitored
    ]
    if !isempty(residual)
        max_excess_mw = maximum(last(loading[name]) for name in residual)
        @warn "Monitored corridors above their limits (PTDF cutoff)" max_excess_mw corridors =
            sort!(residual)
    end
    model.ext["monitoring_log"] = log
    return
end

# Adding rows to a model loaded in the solver is slow, so the solver is detached while they
# are added; for an LP the previous basis is then restored
function _add_corridors!(
    container::SingleOptimizationContainer,
    transport_model::TransportModel,
    portfolio::PSIP.Portfolio,
    names::Vector{String},
)
    jump_model = get_jump_model(container)
    if get_direct_mode_optimizer(get_settings(container))
        add_monitored_corridors!(container, transport_model, portfolio, names)
        return
    end
    # A MIP whose duals were computed is fixed until the next solve
    if is_milp(container) || !isnothing(container.unfix_discrete_variables)
        # The current solution is the start of the next MIP solve
        variables = JuMP.all_variables(jump_model)
        # Values are read before any is set, since setting one discards the solution
        values = JuMP.value.(variables)
        JuMP.set_start_value.(variables, values)
        basis = nothing
    else
        basis = _get_basis(jump_model)
    end
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

# New flow variables are basic, so the equalities that set them are nonbasic
_new_row_status(::MOI.EqualTo) = MOI.NONBASIC
_new_row_status(::MOI.AbstractScalarSet) = MOI.BASIC

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
Log of each solve of a model solved with [`IterativeMonitoring`](@ref).
"""
get_monitoring_log(model::InvestmentModel{IterativeMonitoring}) =
    model.ext["monitoring_log"]

"""
Corridors whose flow is limited in a model with the `NodalPTDFModel` transport model.
"""
get_monitored_corridors(model::InvestmentModel) =
    sort!(collect(get_network_data(get_transport_model(get_template(model))).monitored))
