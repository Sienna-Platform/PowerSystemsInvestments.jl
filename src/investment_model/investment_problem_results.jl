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
Results from an investment model with its investment intervals and operational time
mapping.

Construct from a solved `InvestmentModel` or load from a directory saved by `solve!` or
`serialize_results`. Loaded results have no attached portfolio. Use `set_portfolio!` to
attach it.

Use `get_investment_time_stamps` for investment intervals and `get_timestamps` for
operational timestamps. `OptimizationProblemResults(results)` returns the underlying
optimization results.
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
    if metadata.results_hash !=
       IS.compute_sha256(joinpath(directory, "problem_results.bin"))
        throw(
            ArgumentError("The investment time mapping does not match the saved results."),
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

"""
Return timestamps for a result key. Investment entries use period starts and
weighted-energy expressions use operational slice starts. Other operational entries use
the model's operational timestamps.
"""
function get_timestamps(
    results::InvestmentProblemResults,
    key::Union{VariableKey, ExpressionKey},
)
    entry_type = get_entry_type(key)
    if is_investment_entry(entry_type)
        return Dates.DateTime.(first.(get_investment_time_stamps(results)))
    elseif entry_type <: Union{
        WeightedEnergyGeneration,
        WeightedEnergyDemand,
        WeightedEnergyShareGeneration,
        WeightedEnergyShareDemand,
    }
        mapping = get_time_mapping(results)
        slices = get_consecutive_slices(mapping)[get_operational_indexes(mapping)]
        return get_timestamps(results)[first.(slices)]
    elseif is_operation_entry(entry_type)
        return get_timestamps(results)
    end
    throw(ArgumentError("No result time axis is defined for $entry_type."))
end

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

function ISOPT.read_variable(results::InvestmentProblemResults, args...; kwargs...)
    key = ISOPT._deserialize_key(VariableKey, results.results, args...)
    return read_variable(results, key; kwargs...)
end

ISOPT.read_variable(results::InvestmentProblemResults, key::VariableKey; kwargs...) =
    read_results_with_keys(results, [key]; kwargs...)[key]

ISOPT.read_variables(results::InvestmentProblemResults, entries; kwargs...) =
    ISOPT.read_variables(results, [VariableKey(x...) for x in entries]; kwargs...)

function ISOPT.read_variables(
    results::InvestmentProblemResults,
    entries::Vector{<:AbstractString};
    kwargs...,
)
    return ISOPT.read_variables(
        results,
        [ISOPT._deserialize_key(VariableKey, results.results, name) for name in entries];
        kwargs...,
    )
end

function ISOPT.read_variables(
    results::InvestmentProblemResults,
    entries::Vector{<:OptimizationContainerKey};
    kwargs...,
)
    tables = read_results_with_keys(results, entries; kwargs...)
    return Dict(encode_key_as_string(key) => table for (key, table) in tables)
end

function ISOPT.read_expression(results::InvestmentProblemResults, args...; kwargs...)
    key = ISOPT._deserialize_key(ExpressionKey, results.results, args...)
    return read_expression(results, key; kwargs...)
end

ISOPT.read_expression(results::InvestmentProblemResults, key::ExpressionKey; kwargs...) =
    read_results_with_keys(results, [key]; kwargs...)[key]

ISOPT.read_expressions(results::InvestmentProblemResults; kwargs...) =
    ISOPT.read_expressions(results, list_expression_keys(results); kwargs...)
ISOPT.read_expressions(results::InvestmentProblemResults, entries; kwargs...) =
    ISOPT.read_expressions(results, [ExpressionKey(x...) for x in entries]; kwargs...)

function ISOPT.read_expressions(
    results::InvestmentProblemResults,
    entries::Vector{<:AbstractString};
    kwargs...,
)
    return ISOPT.read_expressions(
        results,
        [ISOPT._deserialize_key(ExpressionKey, results.results, name) for name in entries];
        kwargs...,
    )
end

function ISOPT.read_expressions(
    results::InvestmentProblemResults,
    entries::Vector{<:OptimizationContainerKey};
    kwargs...,
)
    tables = read_results_with_keys(results, entries; kwargs...)
    return Dict(encode_key_as_string(key) => table for (key, table) in tables)
end

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

function ISOPT._process_timestamps(
    results::InvestmentProblemResults,
    key::Union{VariableKey, ExpressionKey},
    start_time::Union{Nothing, Dates.DateTime},
    len::Union{Nothing, Int},
)
    timestamps = get_timestamps(results, key)
    start = isnothing(start_time) ? 1 : findfirst(==(start_time), timestamps)
    isnothing(start) && throw(ArgumentError("start_time is not in the result timestamps."))
    count = isnothing(len) ? length(timestamps) - start + 1 : len
    count > 0 || throw(ArgumentError("len must be positive."))
    stop = start + count - 1
    stop <= length(timestamps) || throw(
        ArgumentError("The requested window exceeds the available result timestamps."),
    )
    indices = start:stop
    return indices, timestamps[indices]
end

"""
Read result tables using each key's time axis. `start_time` must be on that axis and
`len` counts its entries. In a mixed request, the same window arguments are applied
independently to each key. Use `cols` to select a nonempty vector of component names for
variables and expressions. The default `:` reads all components and wide tables preserve
the requested column order.
"""
function read_results_with_keys(
    results::InvestmentProblemResults,
    keys::Vector{<:OptimizationContainerKey};
    start_time::Union{Nothing, Dates.DateTime}=nothing,
    len::Union{Nothing, Int}=nothing,
    table_format::IS.TableFormat=IS.TableFormat.LONG,
    cols::Union{Colon, Vector{String}}=(:),
)
    cols isa Vector &&
        isempty(cols) &&
        throw(ArgumentError("cols must contain at least one component name."))
    tables = Dict{OptimizationContainerKey, DataFrames.DataFrame}()
    for key in keys
        if !(key isa Union{VariableKey, ExpressionKey})
            cols isa Colon || throw(
                ArgumentError(
                    "Column selection is supported for variables and expressions.",
                ),
            )
            merge!(
                tables,
                read_results_with_keys(
                    results.results,
                    [key];
                    start_time=start_time,
                    len=len,
                    table_format=table_format,
                ),
            )
            continue
        end
        values = ISOPT.get_result_values(results, key)
        ISOPT._validate_keys(Base.keys(values), [key])
        table = values[key]
        timestamps = get_timestamps(results, key)
        component_column = ISOPT.get_first_dimension_result_column_name(key)
        if cols isa Vector
            for name in cols
                name in table[!, component_column] || throw(KeyError(name))
            end
            table = filter(component_column => in(cols), table)
        end
        for component in DataFrames.groupby(table, component_column)
            if sort(component.time_index) != eachindex(timestamps)
                throw(
                    ArgumentError(
                        "$(encode_key_as_string(key)) must contain one value per time index " *
                        "for each component.",
                    ),
                )
            end
        end
        indices, selected_timestamps =
            ISOPT._process_timestamps(results, key, start_time, len)
        merge!(
            tables,
            ISOPT._read_results(
                Dict(key => table),
                [key],
                selected_timestamps,
                indices,
                get_model_base_power(results),
                timestamps,
                table_format,
            ),
        )
        if cols isa Vector && table_format == IS.TableFormat.WIDE
            DataFrames.select!(tables[key], ["DateTime"; cols])
        end
    end
    return tables
end

export_results(results::InvestmentProblemResults; kwargs...) =
    export_results(results.results; kwargs...)
export_results(
    results::InvestmentProblemResults,
    exports::OptimizationProblemResultsExport;
    kwargs...,
) = export_results(results.results, exports; kwargs...)

"""
Save investment results and their time mapping in `directory`. The optimization results
remain readable with `OptimizationProblemResults(directory)`. Keep both binary results
files together when moving or copying the saved results.
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
