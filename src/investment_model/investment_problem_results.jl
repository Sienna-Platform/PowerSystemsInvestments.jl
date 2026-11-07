function OptimizationProblemResults(model::InvestmentModel)
    status = get_run_status(model)
    status != RunStatus.SUCCESSFULLY_FINALIZED &&
        error("problem was not solved successfully: $status")

    model_store = get_store(model)

    if isempty(model_store)
        error("Model Solved as part of a Simulation.")
    end

    timestamps = get_time_stamps(model)
    optimizer_stats = IS.Optimization.to_dataframe(get_optimizer_stats(model))
    aux_variable_values =
        Dict(x => read_aux_variable(model, x) for x in list_aux_variable_keys(model))
    variable_values = Dict(x => read_variable(model, x) for x in list_variable_keys(model))
    dual_values = Dict(x => read_dual(model, x) for x in list_dual_keys(model))
    parameter_values = Dict{ParameterKey, DataFrames.DataFrame}()
    expression_values =
        Dict(x => read_expression(model, x) for x in list_expression_keys(model))

    portfolio = get_portfolio(model)
    return OptimizationProblemResults(
        get_problem_base_power(model),
        timestamps,
        portfolio,
        IS.get_uuid(portfolio),
        aux_variable_values,
        variable_values,
        dual_values,
        parameter_values,
        expression_values,
        optimizer_stats,
        get_metadata(get_optimization_container(model)),
        IS.strip_module_name(typeof(model)),
        mkpath(joinpath(get_output_dir(model), "results")),
        get_output_dir(model),
    )
end
