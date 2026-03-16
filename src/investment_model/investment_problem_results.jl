function OptimizationProblemResults(model::InvestmentModel)
    status = get_run_status(model)
    status != RunStatus.SUCCESSFULLY_FINALIZED &&
        error("problem was not solved successfully: $status")

    model_store = get_store(model)

    if isempty(model_store)
        error("Model Solved as part of a Simulation.")
    end

    timestamps = get_time_stamps(model)
    optimizer_stats = IOM.to_dataframe(get_optimizer_stats(model))
    aux_variable_values =
        Dict(x => read_aux_variable(model, x) for x in list_aux_variable_keys(model))
    variable_values = Dict(x => read_variable(model, x) for x in list_variable_keys(model))
    dual_values = Dict(x => read_dual(model, x) for x in list_dual_keys(model))
    parameter_values = Dict()
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
        get_output_dir(model),
        mkpath(joinpath(get_output_dir(model), "results")),
    )
end

list_variable_keys(res::OptimizationProblemResults) = keys(res.variable_values)
list_aux_variable_keys(res::OptimizationProblemResults) = keys(res.aux_variable_values)
list_dual_keys(res::OptimizationProblemResults) = keys(res.dual_values)
list_expression_keys(res::OptimizationProblemResults) = keys(res.expression_values)

list_variable_names(res::OptimizationProblemResults) =
    encode_keys_as_strings(list_variable_keys(res))
list_aux_variable_names(res::OptimizationProblemResults) =
    encode_keys_as_strings(list_aux_variable_keys(res))
list_dual_names(res::OptimizationProblemResults) =
    encode_keys_as_strings(list_dual_keys(res))
list_expression_names(res::OptimizationProblemResults) =
    encode_keys_as_strings(list_expression_keys(res))
