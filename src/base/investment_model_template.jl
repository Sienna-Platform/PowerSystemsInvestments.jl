abstract type AbstractInvestmentModelTemplate end

mutable struct InvestmentModelTemplate <: AbstractInvestmentModelTemplate
    capital_model::CapitalCostModel
    operation_model::OperationCostModel
    feasibility_model::FeasibilityModel
    transport_model::TransportModel{<:AbstractTransportAggregation}
    technology_models::Dict # Type to be refined later
    branch_models::Dict # rename?

    function InvestmentModelTemplate(
        capital_model::CapitalCostModel,
        operation_model::OperationCostModel,
        feasibility_model::FeasibilityModel,
        transport_model::TransportModel{T},
    ) where {T <: AbstractTransportAggregation}
        new(
            capital_model,
            operation_model,
            feasibility_model,
            transport_model,
            Dict(),
            Dict(),
        )
    end
end

function Base.isempty(template::InvestmentModelTemplate)
    if !isempty(template.technologies)
        return false
    else
        return true
    end
end

InvestmentModelTemplate(::Type{T}) where {T <: AbstractTransportAggregation} =
    InvestmentModelTemplate(TransportModel(T))
InvestmentModelTemplate() = InvestmentModelTemplate(SingleRegionPowerModel)

get_technology_models(template::InvestmentModelTemplate) = template.technology_models
get_branch_models(template::InvestmentModelTemplate) = template.branch_models
get_transport_model(template::InvestmentModelTemplate) = template.transport_model
get_transport_formulation(::TransportModel{T}) where {T <: AbstractTransportAggregation} = T

get_capital_model(template::InvestmentModelTemplate) = template.capital_model
get_operation_model(template::InvestmentModelTemplate) = template.operation_model
get_feasibility_model(template::InvestmentModelTemplate) = template.feasibility_model

"""
Sets the network model in a template.
"""
function set_transport_model!(
    template::InvestmentModelTemplate,
    model::TransportModel{<:AbstractTransportAggregation},
)
    template.transport_model = model
    return
end

function set_technology_model!(
    template::InvestmentModelTemplate,
    names::Vector{String},
    component_type::Type{<:PSIP.Technology},
    investment_formulation::Type{<:InvestmentTechnologyFormulation},
    operations_formulation::Type{<:OperationsTechnologyFormulation},
    feasibility_formulation::Type{<:FeasibilityTechnologyFormulation},
)
    set_technology_model!(
        template,
        names,
        TechnologyModel(
            component_type,
            investment_formulation,
            operations_formulation,
            feasibility_formulation,
        ),
    )
    return
end

function set_technology_model!(
    template::InvestmentModelTemplate,
    names::Vector{String},
    model::TechnologyModel{
        <:PSIP.Technology,
        <:InvestmentTechnologyFormulation,
        <:OperationsTechnologyFormulation,
        <:FeasibilityTechnologyFormulation,
    },
)
    _set_model!(template.technology_models, names, model)
    return
end

function set_technology_model!(
    template::InvestmentModelTemplate,
    names::Vector{String},
    model::TechnologyModel{
        <:GenericTransportTechnology,
        <:InvestmentTechnologyFormulation,
        <:OperationsTechnologyFormulation,
        <:FeasibilityTechnologyFormulation,
    },
)
    _set_model!(template.branch_models, names, model)
    return
end

function metadata_string(
    model::TechnologyModel{T, B, C, D},
) where {
    T <: PSIP.Technology,
    B <: InvestmentTechnologyFormulation,
    C <: BasicDispatch,
    D <: FeasibilityTechnologyFormulation,
}
    inv = IS.strip_module_name(B)
    ops = IS.strip_module_name(C)
    fes = IS.strip_module_name(D)

    return string(inv, ops, fes)
end
