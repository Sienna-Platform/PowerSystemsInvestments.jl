mutable struct TechnologyModel{
    D <: PSIP.Technology,
    B <: InvestmentTechnologyFormulation,
    C <: OperationsTechnologyFormulation,
}
    use_slacks::Bool
    time_series_names::Dict{Type{<:TimeSeriesParameter}, String}
    attributes::Dict{String, Any}
end

function _check_technology_formulation(
    ::Type{D},
    ::Type{B},
    ::Type{C},
) where {
    D <: Union{AbstractTechnologyFormulation, PSIP.Technology},
    B <: Union{AbstractTechnologyFormulation, PSIP.Technology},
    C <: Union{AbstractTechnologyFormulation, PSIP.Technology},
}
    if !isconcretetype(D)
        throw(
            ArgumentError(
                "The technology model must contain only concrete types, $(D) is an Abstract Type",
            ),
        )
    end

    if !isconcretetype(B)
        throw(
            ArgumentError(
                "The technology model must contain only concrete types, $(B) is an Abstract Type",
            ),
        )
    end

    if !isconcretetype(C)
        throw(
            ArgumentError(
                "The technology model must contain only concrete types, $(C) is an Abstract Type",
            ),
        )
    end
end

function _set_model!(
    dict::Dict,
    model::TechnologyModel{D, B, C},
) where {
    D <: PSIP.Technology,
    B <: InvestmentTechnologyFormulation,
    C <: OperationsTechnologyFormulation,
}
    key = Symbol(D)
    if haskey(dict, key)
        @warn "Overwriting $(D) existing model"
    end
    dict[key] = model
    return
end

get_technology_type(
    ::TechnologyModel{D, B, C},
) where {
    D <: PSIP.Technology,
    B <: InvestmentTechnologyFormulation,
    C <: OperationsTechnologyFormulation,
} = D

get_investment_formulation(
    ::TechnologyModel{D, B, C},
) where {
    D <: PSIP.Technology,
    B <: InvestmentTechnologyFormulation,
    C <: OperationsTechnologyFormulation,
} = B

get_operations_formulation(
    ::TechnologyModel{D, B, C},
) where {
    D <: PSIP.Technology,
    B <: InvestmentTechnologyFormulation,
    C <: OperationsTechnologyFormulation,
} = C

function TechnologyModel(
    ::Type{D},
    ::Type{B},
    ::Type{C};
    use_slacks=false,
    duals=Vector{DataType}(),
    time_series_names=get_default_time_series_names(D, B, C),
    attributes=Dict{String, Any}(),
) where {
    D <: PSIP.SupplyTechnology{T},
    B <: ContinuousInvestment,
    C <: BasicDispatch,
} where {T <: PSY.StaticInjection}
    attributes_ = get_default_attributes(D, B, C)
    for (k, v) in attributes
        attributes_[k] = v
    end

    _check_technology_formulation(D, B, C)
    #TODO: new is only defined for inner constructors, replace for now but we might want to reorganize this file later
    #new{D, B, C}(use_slacks, duals, time_series_names, attributes_, nothing)
    return TechnologyModel{D, B, C}(
        use_slacks,
        duals,
        time_series_names,
        attributes_,
        nothing,
    )
end
