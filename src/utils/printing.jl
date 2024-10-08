# InvestmentModelTemplate

function Base.show(io::IO, ::MIME"text/plain", input::InvestmentModelTemplate)
    _show_method(io, input, :auto)
end

function Base.show(io::IO, ::MIME"text/html", input::InvestmentModelTemplate)
    _show_method(io, input, :html; standalone=false, tf=PrettyTables.tf_html_simple)
end

function _show_method(io::IO, template::InvestmentModelTemplate, backend::Symbol; kwargs...)
    #=
    table = [
        "Network Model" string(get_network_formulation(template.network_model))
        "Slacks" get_use_slacks(template.network_model)
        "PTDF" !isnothing(get_PTDF_matrix(template.network_model))
        "Duals" isempty(get_duals(template.network_model)) ? "None" : string.(get_duals(template.network_model))
    ]

    PrettyTables.pretty_table(
        io,
        table;
        backend=Val(backend),
        show_header=false,
        title="Network Model",
        alignment=:l,
        kwargs...,
    )

    println(io)
    header =
        ["Technology Type", "Investment Formulation", "Operations Formulation", "Slacks"]

    table = Matrix{String}(undef, length(template.technologies), length(header))
    for (ix, model) in enumerate(values(template.technologies))
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
    =#
    return
end
