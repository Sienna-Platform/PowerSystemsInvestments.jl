mutable struct TechnologyModel{
    D<:PSIP.Technology,
    A<:InvestmentTechnologyFormulation,
    B<:OperationsTechnologyFormulation,
    C<:FeasibilityTechnologyFormulation,
}
    use_slacks::Bool
    duals::Vector{DataType}
    attributes::Dict{String,Any}
end

function _set_model!(
    dict::Dict,
    names::Vector{String},
    model::TechnologyModel{D,A,B,C},
) where {
    D<:PSIP.Technology,
    A<:InvestmentTechnologyFormulation,
    B<:OperationsTechnologyFormulation,
    C<:FeasibilityTechnologyFormulation,
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
    ::TechnologyModel{D,A,B,C},
) where {
    D<:PSIP.Technology,
    A<:InvestmentTechnologyFormulation,
    B<:OperationsTechnologyFormulation,
    C<:FeasibilityTechnologyFormulation,
} = D

get_investment_formulation(
    ::TechnologyModel{D,A,B,C},
) where {
    D<:PSIP.Technology,
    A<:InvestmentTechnologyFormulation,
    B<:OperationsTechnologyFormulation,
    C<:FeasibilityTechnologyFormulation,
} = A

get_operations_formulation(
    ::TechnologyModel{D,A,B,C},
) where {
    D<:PSIP.Technology,
    A<:InvestmentTechnologyFormulation,
    B<:OperationsTechnologyFormulation,
    C<:FeasibilityTechnologyFormulation,
} = B

get_feasibility_formulation(
    ::TechnologyModel{D,A,B,C},
) where {
    D<:PSIP.Technology,
    A<:InvestmentTechnologyFormulation,
    B<:OperationsTechnologyFormulation,
    C<:FeasibilityTechnologyFormulation,
} = C

function TechnologyModel(
    ::Type{D},
    ::Type{A},
    ::Type{B},
    ::Type{C};
    use_slacks=false,
    duals=Vector{DataType}(),
    attributes=Dict{String,Any}(),
) where {
    D<:PSIP.Technology,
    A<:InvestmentTechnologyFormulation,
    B<:OperationsTechnologyFormulation,
    C<:FeasibilityTechnologyFormulation,
}
    attributes_ = get_default_attributes(D, A, B, C)
    for (k, v) in attributes
        attributes_[k] = v
    end

    #_check_technology_formulation(D, A, B, C)
    #TODO: new is only defined for inner constructors, replace for now but we might want to reorganize this file later
    #new{D, B, C}(use_slacks, duals, time_series_names, attributes_, nothing)
    return TechnologyModel{D,A,B,C}(use_slacks, duals, attributes_)
end
