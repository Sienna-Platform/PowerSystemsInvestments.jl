mutable struct TechnologyModel{
    D <: PSIP.Technology,
    A <: InvestmentTechnologyFormulation,
    B <: OperationsTechnologyFormulation,
    C <: FeasibilityTechnologyFormulation,
}
    use_slacks::Bool
    duals::Vector{DataType}
    attributes::Dict{String, Any}
end

function _set_model!(
    dict::Dict,
    names::Vector{String},
    model::TechnologyModel{D, A, B, C},
) where {
    D <: PSIP.Technology,
    A <: InvestmentTechnologyFormulation,
    B <: OperationsTechnologyFormulation,
    C <: FeasibilityTechnologyFormulation,
}
    #key = Symbol(model)
    key = model
    if haskey(dict, key)
        @warn "Overwriting $(D) existing model"
    end
    dict[key] = names
    return
end

get_technology_type(
    ::TechnologyModel{D, A, B, C},
) where {
    D <: PSIP.Technology,
    A <: InvestmentTechnologyFormulation,
    B <: OperationsTechnologyFormulation,
    C <: FeasibilityTechnologyFormulation,
} = D

get_investment_formulation(
    ::TechnologyModel{D, A, B, C},
) where {
    D <: PSIP.Technology,
    A <: InvestmentTechnologyFormulation,
    B <: OperationsTechnologyFormulation,
    C <: FeasibilityTechnologyFormulation,
} = A

get_operations_formulation(
    ::TechnologyModel{D, A, B, C},
) where {
    D <: PSIP.Technology,
    A <: InvestmentTechnologyFormulation,
    B <: OperationsTechnologyFormulation,
    C <: FeasibilityTechnologyFormulation,
} = B

get_feasibility_formulation(
    ::TechnologyModel{D, A, B, C},
) where {
    D <: PSIP.Technology,
    A <: InvestmentTechnologyFormulation,
    B <: OperationsTechnologyFormulation,
    C <: FeasibilityTechnologyFormulation,
} = C

_supported_investment_formulations(::Type{<:PSIP.Technology}) = nothing

function _check_investment_formulation(
    ::Type{D},
    ::Type{A},
) where {D <: PSIP.Technology, A <: InvestmentTechnologyFormulation}
    supported_formulations = _supported_investment_formulations(D)
    isnothing(supported_formulations) && return
    any(A <: formulation for formulation in supported_formulations) && return

    supported_names = if isempty(supported_formulations)
        "none"
    else
        join(nameof.(supported_formulations), ", ")
    end

    throw(
        ArgumentError(
            "$(nameof(A)) is currently not supported for $(nameof(D)). " *
            "Supported investment formulations: $supported_names.",
        ),
    )
end

function TechnologyModel(
    ::Type{D},
    ::Type{A},
    ::Type{B},
    ::Type{C};
    use_slacks=false,
    duals=Vector{DataType}(),
    attributes=Dict{String, Any}(),
) where {
    D <: PSIP.Technology,
    A <: InvestmentTechnologyFormulation,
    B <: OperationsTechnologyFormulation,
    C <: FeasibilityTechnologyFormulation,
}
    _check_investment_formulation(D, A)

    attributes_ = get_default_attributes(D, A, B, C)
    for (k, v) in attributes
        attributes_[k] = v
    end

    # TODO: new is only defined for inner constructors, replace for now but we might want to reorganize this file later
    #new{D, B, C}(use_slacks, duals, time_series_names, attributes_, nothing)
    return TechnologyModel{D, A, B, C}(use_slacks, duals, attributes_)
end
