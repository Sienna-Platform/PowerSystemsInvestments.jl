# PrettyTables v3 removed predefined HTML table format recipes.
# This reproduces the v2 tf_html_simple CSS for backwards-compatible Jupyter output.
const tf_html_simple = PrettyTables.HtmlTableFormat(; css="""
                                                    table, td, th {
                                                        border-collapse: collapse;
                                                        font-family: sans-serif;
                                                    }

                                                    td, th {
                                                        border-bottom: 0;
                                                        padding: 4px
                                                    }

                                                    tr:nth-child(odd) {
                                                        background: #eee;
                                                    }

                                                    tr:nth-child(even) {
                                                        background: #fff;
                                                    }

                                                    tr.header {
                                                        background: #fff !important;
                                                        font-weight: bold;
                                                    }

                                                    tr.subheader {
                                                        background: #fff !important;
                                                        color: dimgray;
                                                    }

                                                    tr.headerLastRow {
                                                        border-bottom: 2px solid black;
                                                    }

                                                    th.rowNumber, td.rowNumber {
                                                        text-align: right;
                                                    }
                                                    """)

function Base.show(io::IO, ::MIME"text/plain", input::InvestmentModelTemplate)
    _show_method(io, input, :auto)
end

function Base.show(io::IO, ::MIME"text/html", input::InvestmentModelTemplate)
    _show_method(io, input, :html; stand_alone=false, table_format=tf_html_simple)
end

function _show_method(io::IO, template::InvestmentModelTemplate, backend::Symbol; kwargs...)
    table = [
        "Transport Model" string(get_transport_formulation(get_transport_model(template)))
        "Capital Model" string(typeof(get_capital_model(template)))
        "Operation Model" string(typeof(get_operation_model(template)))
        "Feasibility Model" string(typeof(get_feasibility_model(template)))
    ]

    PrettyTables.pretty_table(
        io,
        table;
        backend=backend,
        show_column_labels=false,
        title="Template Model",
        alignment=:l,
        kwargs...,
    )

    println(io)
    column_labels =
        ["Technology Type", "Investment Formulation", "Operations Formulation", "Slacks"]

    table = Matrix{String}(undef, length(template.technology_models), length(column_labels))
    for (ix, model) in enumerate(keys(template.technology_models))
        table[ix, 1] = string(get_technology_type(model))
        table[ix, 2] = string(get_investment_formulation(model))
        table[ix, 3] = string(get_operations_formulation(model))
        table[ix, 4] = string(model.use_slacks)
    end

    PrettyTables.pretty_table(
        io,
        table;
        backend=backend,
        column_labels=column_labels,
        title="Technology Models",
        alignment=:l,
    )

    println(io)
    requirement_labels = ["Requirement Type", "Requirement Name", "Formulation"]
    table = Matrix{String}(
        undef,
        length(template.requirement_models),
        length(requirement_labels),
    )
    for (ix, model) in enumerate(keys(template.requirement_models))
        table[ix, 1] = string(get_requirement_type(model))
        table[ix, 2] = only(template.requirement_models[model])
        table[ix, 3] = string(get_requirement_formulation(model))
    end

    PrettyTables.pretty_table(
        io,
        table;
        backend=backend,
        column_labels=requirement_labels,
        title="Requirement Models",
        alignment=:l,
    )
    return
end

function Base.show(io::IO, ::MIME"text/plain", input::InvestmentModel)
    _show_method(io, input.template, :auto)
end

function Base.show(io::IO, ::MIME"text/html", input::InvestmentModel)
    _show_method(io, input.template, :html; stand_alone=false, table_format=tf_html_simple)
end

function Base.show(io::IO, ::MIME"text/plain", input::OptimizationProblemResults)
    _show_method(io, input, :auto)
end

function Base.show(io::IO, ::MIME"text/html", input::OptimizationProblemResults)
    _show_method(io, input, :html; stand_alone=false, table_format=tf_html_simple)
end

function Base.show(io::IO, ::MIME"text/plain", input::InvestmentProblemResults)
    _show_method(io, input, :auto)
end

function Base.show(io::IO, ::MIME"text/html", input::InvestmentProblemResults)
    _show_method(io, input, :html; stand_alone=false, table_format=tf_html_simple)
end

function _show_method(io::IO, results::InvestmentProblemResults, backend::Symbol; kwargs...)
    time_mapping = get_time_mapping(results)
    periods = get_investment_time_stamps(time_mapping)
    if !isempty(periods)
        column_labels = ["Period", "Start", "End"]
        table = Matrix{String}(undef, length(periods), length(column_labels))
        for (ix, (start_time, end_time)) in enumerate(periods)
            table[ix, 1] = string(ix)
            table[ix, 2] = string(start_time)
            table[ix, 3] = string(end_time)
        end
        PrettyTables.pretty_table(
            io,
            table;
            backend=backend,
            column_labels=column_labels,
            title="Investment Periods ($(length(periods)))",
            alignment=:l,
            kwargs...,
        )
    end

    slices = get_consecutive_slices(time_mapping)[get_operational_indexes(time_mapping)]
    timestamps = get_time_stamps(time_mapping)
    if !isempty(slices)
        column_labels = ["Slice", "Start", "End", "Timestamps", "Resolution"]
        table = Matrix{String}(undef, length(slices), length(column_labels))
        for (ix, indexes) in enumerate(slices)
            intervals = unique(diff(timestamps[indexes]))
            resolution = if isempty(intervals)
                "N/A (single timestamp)"
            elseif length(intervals) == 1 && only(intervals) > Dates.Millisecond(0)
                string(Dates.canonicalize(only(intervals)))
            else
                "Irregular"
            end
            table[ix, 1] = string(ix)
            table[ix, 2] = string(timestamps[first(indexes)])
            table[ix, 3] = string(timestamps[last(indexes)])
            table[ix, 4] = string(length(indexes))
            table[ix, 5] = resolution
        end
        println(io)
        PrettyTables.pretty_table(
            io,
            table;
            backend=backend,
            column_labels=column_labels,
            title="Operational Slices ($(length(slices))), Timestamps ($(sum(length, slices)))",
            alignment=:l,
            kwargs...,
        )
    end
    _show_method(io, OptimizationProblemResults(results), backend; kwargs...)
end

function _show_method(
    io::IO,
    results::T,
    backend::Symbol;
    kwargs...,
) where {T <: OptimizationProblemResults}
    values = Dict{String, Vector{String}}(
        "Variables" => list_variable_names(results),
        "Auxiliary variables" => list_aux_variable_names(results),
        "Duals" => list_dual_names(results),
        "Expressions" => list_expression_names(results),
    )

    if hasfield(T, :problem)
        name = results.problem
    else
        name = "PowerSystemsInvestments"
    end

    if backend == :auto
        extra = (; display_size=(-1, -1))
    else
        extra = (;)
    end
    for (k, val) in values
        if !isempty(val)
            println(io)
            PrettyTables.pretty_table(
                io,
                val;
                show_column_labels=false,
                backend=backend,
                title="$name Problem $k Results",
                alignment=:l,
                extra...,
                kwargs...,
            )
        end
    end
end

function _print_conflict_table(io::IO, key, conflict_indices::Vector)
    PrettyTables.pretty_table(
        io,
        conflict_indices;
        column_labels=[string(key)],
        display_size=(-1, -1),
    )
    return
end
