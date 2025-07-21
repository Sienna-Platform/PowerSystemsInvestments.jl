const _SERIALIZED_MODEL_FILENAME = "model.bin"

struct OptimizerAttributes
    name::String
    version::String
    attributes::Any
end

function OptimizerAttributes(model::InvestmentModel, optimizer::MOI.OptimizerWithAttributes)
    jump_model = get_jump_model(model)
    name = JuMP.solver_name(jump_model)
    # Note that this uses private field access to MOI.OptimizerWithAttributes because there
    # is no public method available.
    # This could break if MOI changes their implementation.
    try
        version = MOI.get(JuMP.backend(jump_model), MOI.SolverVersion())
        return OptimizerAttributes(name, version, optimizer.params)
    catch
        @debug "Solver Version not supported by the solver"
        version = "MOI.SolverVersion not supported"
        return OptimizerAttributes(name, version, optimizer.params)
    end
end

function _get_optimizer_attributes(model::InvestmentModel)
    return get_optimizer(get_settings(model)).params
end

struct ProblemSerializationWrapper
    template::InvestmentModelTemplate
    sys::Union{Nothing, String}
    settings::Settings
    model_type::DataType
    name::String
    optimizer::OptimizerAttributes
end

function serialize_problem(model::InvestmentModel; optimizer=nothing)
    # A PowerSystem cannot be serialized in this format because of how it stores
    # time series data. Use its specialized serialization method instead.
    portfolio_to_file = get_portfolio_to_file(get_settings(model))
    if portfolio_to_file
        portfolio = get_portfolio(model)
        portfolio_filename =
            joinpath(get_output_dir(model), make_portfolio_filename(portfolio))
        # Skip serialization if the system is already in the folder
        !ispath(portfolio_filename) && PSIP.to_json(portfolio, portfolio_filename)
    else
        portfolio_filename = nothing
    end
    container = get_optimization_container(model)

    if optimizer === nothing
        optimizer = get_optimizer(get_settings(model))
        @assert optimizer !== nothing "optimizer must be passed if it wasn't saved in Settings"
    end

    obj = ProblemSerializationWrapper(
        model.template,
        portfolio_filename,
        container.settings_copy,
        typeof(model),
        string(get_name(model)),
        OptimizerAttributes(model, optimizer),
    )
    bin_file_name = joinpath(get_output_dir(model), _SERIALIZED_MODEL_FILENAME)
    Serialization.serialize(bin_file_name, obj)
    @info "Serialized OperationModel to" bin_file_name
end
