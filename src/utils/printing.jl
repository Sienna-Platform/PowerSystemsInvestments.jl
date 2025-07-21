# InvestmentModelTemplate

function Base.show(io::IO, ::MIME"text/plain", input::InvestmentModelTemplate)
    _show_method(io, input, :auto)
end

function Base.show(io::IO, ::MIME"text/html", input::InvestmentModelTemplate)
    _show_method(io, input, :html; standalone=false, tf=PrettyTables.tf_html_simple)
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
        backend=Val(backend),
        show_header=false,
        title="Template Model",
        alignment=:l,
        kwargs...,
    )

    println(io)
    header =
        ["Technology Type", "Investment Formulation", "Operations Formulation", "Slacks"]

    table = Matrix{String}(undef, length(template.technology_models), length(header))
    for (ix, model) in enumerate(keys(template.technology_models))
        table[ix, 1] = string(get_technology_type(model))
        table[ix, 2] = string(get_investment_formulation(model))
        table[ix, 3] = string(get_operations_formulation(model))
        table[ix, 4] = string(model.use_slacks)
    end

    PrettyTables.pretty_table(
        io,
        table;
        backend=Val(backend),
        header=header,
        title="Technology Models",
        alignment=:l,
    )
    return
end

function Base.show(io::IO, ::MIME"text/plain", input::InvestmentModel)
    _show_method(io, input.template, :auto)
end

function Base.show(io::IO, ::MIME"text/html", input::InvestmentModel)
    _show_method(
        io,
        input.template,
        :html;
        standalone=false,
        tf=PrettyTables.tf_html_simple,
    )
end

function Base.show(io::IO, ::MIME"text/plain", input::OptimizationProblemResults)
    _show_method(io, input, :auto)
end

function Base.show(io::IO, ::MIME"text/html", input::OptimizationProblemResults)
    _show_method(io, input, :html; standalone=false, tf=PrettyTables.tf_html_simple)
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

    for (k, val) in values
        if !isempty(val)
            println(io)
            PrettyTables.pretty_table(
                io,
                val;
                show_header=false,
                backend=Val(backend),
                title="$name Problem $k Results",
                alignment=:l,
                kwargs...,
            )
        end
    end
end
