function build_impl!(model::InvestmentModel{SingleInstanceSolve})
    build_pre_step!(model)

    build_model!(
        get_optimization_container(model),
        get_template(model),
        get_portfolio(model),
    )
    try
        serialize_metadata!(get_optimization_container(model), get_output_dir(model))
    catch e
        @warn "serialize_metadata! skipped: $e"
    end
    return
end
