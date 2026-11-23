_check_monitoring_transport(::TransportModel{NodalPTDFModel}) = nothing
_check_monitoring_transport(::TransportModel{T}) where {T} =
    error("IterativeMonitoring requires the NodalPTDFModel transport model, not $T")

function build_impl!(model::InvestmentModel{IterativeMonitoring})
    transport_model = get_transport_model(get_template(model))
    _check_monitoring_transport(transport_model)
    build_single_instance!(model; monitor_iteratively=true)
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
    # Undoes the screening changes if a solve fails
    try
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
            added = capped ? String[] : sort!(new_overloads)
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
        # Only possible with a relative PTDF tolerance
        residual = [
            name for (name, (ratio, _)) in loading if
            ratio > 1 + tolerance && name in network.monitored
        ]
        if !isempty(residual)
            max_excess_mw = maximum(last(loading[name]) for name in residual)
            @warn "Monitored corridors above their limits (PTDF relative tolerance)" max_excess_mw corridors =
                sort!(residual)
        end
    finally
        isnothing(undo_relax) || undo_relax()
        isnothing(target_gap) ||
            JuMP.set_attribute(jump_model, MOI.RelativeGapTolerance(), target_gap)
    end
    model.ext["monitoring_log"] = log
    return
end

function _add_corridors!(
    container::SingleOptimizationContainer,
    transport_model::TransportModel,
    portfolio::PSIP.Portfolio,
    names::Vector{String},
)
    jump_model = get_jump_model(container)
    if JuMP.mode(jump_model) == JuMP.DIRECT
        add_monitored_corridors!(container, transport_model, portfolio, names)
        return
    end
    variables = JuMP.all_variables(jump_model)
    constraints =
        JuMP.all_constraints(jump_model; include_variable_in_set_constraints=false)
    basis = nothing
    if is_milp(container)
        # Values are read before any start is set, since setting one discards the solution
        values = JuMP.value.(variables)
        JuMP.set_start_value.(variables, values)
    else
        try
            basis = (
                Dict(
                    zip(
                        variables,
                        MOI.get.(jump_model, MOI.VariableBasisStatus(), variables),
                    ),
                ),
                Dict(
                    zip(
                        constraints,
                        MOI.get.(jump_model, MOI.ConstraintBasisStatus(), constraints),
                    ),
                ),
            )
        catch err
            err isa Union{MOI.GetAttributeNotAllowed, MOI.UnsupportedAttribute} || rethrow()
            @info "The solver has no basis, so the next solves are not warm-started" maxlog =
                1
        end
    end
    MOI.Utilities.reset_optimizer(jump_model)
    add_monitored_corridors!(container, transport_model, portfolio, names)
    isnothing(basis) && return
    variable_status, constraint_status = basis
    backend = JuMP.backend(jump_model)
    MOI.Utilities.attach_optimizer(backend)
    index_map = backend.model_to_optimizer_map
    try
        for v in JuMP.all_variables(jump_model)
            status = get(variable_status, v, MOI.BASIC)
            MOI.set(
                backend.optimizer,
                MOI.VariableBasisStatus(),
                index_map[JuMP.index(v)],
                status,
            )
        end
        for c in JuMP.all_constraints(jump_model; include_variable_in_set_constraints=false)
            status = get(
                () -> _new_row_status(JuMP.constraint_object(c).set),
                constraint_status,
                c,
            )
            MOI.set(
                backend.optimizer,
                MOI.ConstraintBasisStatus(),
                index_map[JuMP.index(c)],
                status,
            )
        end
    catch err
        err isa Union{MOI.UnsupportedAttribute, MOI.SetAttributeNotAllowed} || rethrow()
        @info "The solver cannot set a basis, so the next solves are not warm-started" maxlog =
            1
        # Drops any statuses already set
        MOI.Utilities.reset_optimizer(jump_model)
    end
    return
end

# New flow variables are basic, so the equalities that set them are nonbasic
_new_row_status(::MOI.EqualTo) = MOI.NONBASIC
_new_row_status(::MOI.AbstractScalarSet) = MOI.BASIC

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
