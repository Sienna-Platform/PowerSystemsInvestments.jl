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

"""
Return the portfolio attached to the results or `nothing` when no source is attached.
"""
get_portfolio(results::OptimizationProblemResults) = ISOPT.get_source_data(results)

"""
Attach a portfolio with the same UUID as the source used to solve the model.

Returns `nothing`.
"""
set_portfolio!(results::OptimizationProblemResults, portfolio::PSIP.Portfolio) =
    ISOPT.set_source_data!(results, portfolio)

"""
Results from an investment model with its investment intervals and operational time mapping.

Construct from a solved `InvestmentModel` or load from a directory saved by `solve!` or
`serialize_results`.
Loaded results have no attached portfolio.
Use `set_portfolio!` to attach it.

Use `get_investment_time_stamps` for investment intervals and `get_timestamps` for operational
timestamps.
`OptimizationProblemResults(results)` returns the underlying optimization results.
"""
struct InvestmentProblemResults <: IS.Results
    results::OptimizationProblemResults
    time_mapping::TimeMapping
end

function InvestmentProblemResults(model::InvestmentModel)
    results = OptimizationProblemResults(model)
    results.timestamps = copy(get_timestamps(results))
    time_mapping = deepcopy(get_time_mapping(get_optimization_container(model)))
    return InvestmentProblemResults(results, time_mapping)
end

const _INVESTMENT_RESULTS_METADATA_FILENAME = "investment_results_metadata.bin"

function InvestmentProblemResults(directory::AbstractString)
    filename = joinpath(directory, _INVESTMENT_RESULTS_METADATA_FILENAME)
    if !isfile(filename)
        throw(
            ArgumentError(
                "No investment time mapping exists in $directory. " *
                "Use OptimizationProblemResults for results saved without a time mapping.",
            ),
        )
    end
    metadata = Serialization.deserialize(filename)
    if metadata.results_hash != IS.compute_sha256(joinpath(directory, "problem_results.bin"))
        throw(
            ArgumentError(
                "The investment time mapping does not match the saved results.",
            ),
        )
    end
    results = OptimizationProblemResults(directory)
    if get_timestamps(results) != get_time_stamps(metadata.time_mapping)
        throw(
            ArgumentError(
                "The investment time mapping does not match the result timestamps.",
            ),
        )
    end
    return InvestmentProblemResults(results, metadata.time_mapping)
end

OptimizationProblemResults(results::InvestmentProblemResults) = results.results
get_time_mapping(results::InvestmentProblemResults) = results.time_mapping

"""
Return a copy of the ordered investment intervals used to solve the model.
"""
get_investment_time_stamps(results::InvestmentProblemResults) =
    copy(get_investment_time_stamps(get_time_mapping(results)))

get_portfolio(results::InvestmentProblemResults) = get_portfolio(results.results)
set_portfolio!(results::InvestmentProblemResults, portfolio::PSIP.Portfolio) =
    set_portfolio!(results.results, portfolio)
IS.get_source_data(results::InvestmentProblemResults) = get_portfolio(results)
ISOPT.get_source_data_uuid(results::InvestmentProblemResults) =
    ISOPT.get_source_data_uuid(results.results)
IS.get_timestamp(results::InvestmentProblemResults) = get_timestamps(results)
IS.get_base_power(results::InvestmentProblemResults) = get_model_base_power(results)
IS.get_total_cost(results::InvestmentProblemResults) = get_objective_value(results)
get_timestamps(results::InvestmentProblemResults) = get_timestamps(results.results)
get_model_base_power(results::InvestmentProblemResults) =
    get_model_base_power(results.results)
get_objective_value(results::InvestmentProblemResults, execution=1) =
    get_objective_value(results.results, execution)
get_optimizer_stats(results::InvestmentProblemResults) =
    get_optimizer_stats(results.results)
read_optimizer_stats(results::InvestmentProblemResults) =
    read_optimizer_stats(results.results)
get_output_dir(results::InvestmentProblemResults) = get_output_dir(results.results)
ISOPT.get_results_dir(results::InvestmentProblemResults) =
    ISOPT.get_results_dir(results.results)

get_variable_values(results::InvestmentProblemResults) =
    get_variable_values(results.results)
list_variable_keys(results::InvestmentProblemResults) = list_variable_keys(results.results)
list_variable_names(results::InvestmentProblemResults) =
    list_variable_names(results.results)
get_expression_values(results::InvestmentProblemResults) =
    get_expression_values(results.results)
list_expression_keys(results::InvestmentProblemResults) =
    list_expression_keys(results.results)
list_expression_names(results::InvestmentProblemResults) =
    list_expression_names(results.results)
get_aux_variable_values(results::InvestmentProblemResults) =
    get_aux_variable_values(results.results)
list_aux_variable_keys(results::InvestmentProblemResults) =
    list_aux_variable_keys(results.results)
list_aux_variable_names(results::InvestmentProblemResults) =
    list_aux_variable_names(results.results)
get_parameter_values(results::InvestmentProblemResults) =
    get_parameter_values(results.results)
list_parameter_keys(results::InvestmentProblemResults) =
    list_parameter_keys(results.results)
list_parameter_names(results::InvestmentProblemResults) =
    list_parameter_names(results.results)
get_dual_values(results::InvestmentProblemResults) = get_dual_values(results.results)
list_dual_keys(results::InvestmentProblemResults) = list_dual_keys(results.results)
list_dual_names(results::InvestmentProblemResults) = list_dual_names(results.results)

ISOPT.read_variable(results::InvestmentProblemResults, args...; kwargs...) =
    ISOPT.read_variable(results.results, args...; kwargs...)
ISOPT.read_variables(results::InvestmentProblemResults, entries; kwargs...) =
    ISOPT.read_variables(results.results, entries; kwargs...)
ISOPT.read_expression(results::InvestmentProblemResults, args...; kwargs...) =
    ISOPT.read_expression(results.results, args...; kwargs...)
ISOPT.read_expressions(results::InvestmentProblemResults; kwargs...) =
    ISOPT.read_expressions(results.results; kwargs...)
ISOPT.read_expressions(results::InvestmentProblemResults, entries; kwargs...) =
    ISOPT.read_expressions(results.results, entries; kwargs...)
ISOPT.read_aux_variable(results::InvestmentProblemResults, args...; kwargs...) =
    ISOPT.read_aux_variable(results.results, args...; kwargs...)
ISOPT.read_aux_variables(results::InvestmentProblemResults, entries; kwargs...) =
    ISOPT.read_aux_variables(results.results, entries; kwargs...)
ISOPT.read_parameter(results::InvestmentProblemResults, args...; kwargs...) =
    ISOPT.read_parameter(results.results, args...; kwargs...)
ISOPT.read_parameters(results::InvestmentProblemResults, entries; kwargs...) =
    ISOPT.read_parameters(results.results, entries; kwargs...)
ISOPT.read_dual(results::InvestmentProblemResults, args...; kwargs...) =
    ISOPT.read_dual(results.results, args...; kwargs...)
ISOPT.read_duals(results::InvestmentProblemResults, entries; kwargs...) =
    ISOPT.read_duals(results.results, entries; kwargs...)

ISOPT.get_result_values(results::InvestmentProblemResults, key::OptimizationContainerKey) =
    ISOPT.get_result_values(results.results, key)
read_results_with_keys(
    results::InvestmentProblemResults,
    keys::Vector{<:OptimizationContainerKey};
    kwargs...,
) = read_results_with_keys(results.results, keys; kwargs...)
export_results(results::InvestmentProblemResults; kwargs...) =
    export_results(results.results; kwargs...)
export_results(
    results::InvestmentProblemResults,
    exports::OptimizationProblemResultsExport;
    kwargs...,
) = export_results(results.results, exports; kwargs...)

"""
Save investment results and their time mapping in `directory`.
The optimization results remain readable with `OptimizationProblemResults(directory)`.
Keep both binary results files together when moving or copying the saved results.
"""
function serialize_results(results::InvestmentProblemResults, directory::AbstractString)
    serialize_results(OptimizationProblemResults(results), directory)
    metadata = (
        time_mapping=get_time_mapping(results),
        results_hash=IS.compute_sha256(joinpath(directory, "problem_results.bin")),
    )
    Serialization.serialize(
        joinpath(directory, _INVESTMENT_RESULTS_METADATA_FILENAME),
        metadata,
    )
    return
end
