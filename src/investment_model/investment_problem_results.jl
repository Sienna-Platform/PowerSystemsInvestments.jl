function OptimizationProblemResults(model::InvestmentModel)
    status = get_run_status(model)
    status != RunStatus.SUCCESSFULLY_FINALIZED &&
        error("problem was not solved successfully: $status")

    model_store = get_store(model)

    if isempty(model_store)
        error("Model Solved as part of a Simulation.")
    end

    # Create result wrapper with validated model
    result = ISOPT.OptimizationProblemResults()
    result.model = model
    return result
end

function list_variable_keys(res::ISOPT.OptimizationProblemResults)
    container = get_optimization_container(res.model)
    return isnothing(container) ? [] : collect(keys(container.variables))
end

function list_aux_variable_keys(res::ISOPT.OptimizationProblemResults)
    container = get_optimization_container(res.model)
    return isnothing(container) ? [] : collect(keys(container.aux_variables))
end

function list_dual_keys(res::ISOPT.OptimizationProblemResults)
    container = get_optimization_container(res.model)
    return isnothing(container) ? [] : collect(keys(container.duals))
end

function list_expression_keys(res::ISOPT.OptimizationProblemResults)
    container = get_optimization_container(res.model)
    return isnothing(container) ? [] : collect(keys(container.expressions))
end

function list_variable_names(res::ISOPT.OptimizationProblemResults)
    encode_keys_as_strings(list_variable_keys(res))
end

function list_aux_variable_names(res::ISOPT.OptimizationProblemResults)
    encode_keys_as_strings(list_aux_variable_keys(res))
end

function list_dual_names(res::ISOPT.OptimizationProblemResults)
    encode_keys_as_strings(list_dual_keys(res))
end

function list_expression_names(res::ISOPT.OptimizationProblemResults)
    encode_keys_as_strings(list_expression_keys(res))
end
