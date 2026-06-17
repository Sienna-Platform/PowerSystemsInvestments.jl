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

    extra = backend == :auto ? (; display_size=(-1, -1)) : (;)
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
