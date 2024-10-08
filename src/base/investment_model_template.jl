abstract type AbstractInvestmentModelTemplate end

mutable struct InvestmentModelTemplate <: AbstractInvestmentModelTemplate
    capital_model::CapitalCostModel
    operation_model::OperationCostModel
    feasibility_model::FeasibilityModel
    transport_model::TransportModel{<:AbstractTransportAggregation}
    technology_models::Dict # Type to be refined later

    function InvestmentModelTemplate(
        capital_model::CapitalCostModel,
        operation_model::OperationCostModel,
        feasibility_model::FeasibilityModel,
        transport_model::TransportModel{T},
    ) where {T <: AbstractTransportAggregation}
        new(capital_model, operation_model, feasibility_model, transport_model, Dict())
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

get_technology_models(template::InvestmentModelTemplate) = template.technologies
get_network_model(template::InvestmentModelTemplate) = template.network_model
get_network_formulation(template::InvestmentModelTemplate) =
    get_network_formulation(get_network_model(template))

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

function set_device_model!(
    template::InvestmentModelTemplate,
    component_type::Type{<:PSIP.Technology},
    investment_formulation::Type{<:InvestmentTechnologyFormulation},
    operations_formulation::Type{<:OperationsTechnologyFormulation},
)
    set_device_model!(
        template,
        TechnologyModel(component_type, investment_formulation, operations_formulation),
    )
    return
end

function set_device_model!(
    template::InvestmentModelTemplate,
    model::TechnologyModel{
        <:PSIP.Technology,
        <:InvestmentTechnologyFormulation,
        <:OperationsTechnologyFormulation,
    },
)
    _set_model!(template.technologies, model)
    return
end
