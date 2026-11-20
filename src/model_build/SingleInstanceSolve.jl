function build_impl!(model::InvestmentModel{SingleInstanceSolve})
    build_single_instance!(model)
    return
end

function build_single_instance!(
    model::InvestmentModel;
    default_monitored::Union{Nothing, Vector{String}}=nothing,
)
    build_pre_step!(model)

    build_model!(
        get_optimization_container(model),
        get_template(model),
        get_portfolio(model);
        default_monitored=default_monitored,
    )
    serialize_metadata!(get_optimization_container(model), get_output_dir(model))
    return
end
