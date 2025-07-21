abstract type AbstractInvestmentModelTemplate end

mutable struct InvestmentModelTemplate <: AbstractInvestmentModelTemplate
    capital_model::CapitalCostModel
    operation_model::OperationCostModel
    feasibility_model::FeasibilityModel
    transport_model::TransportModel{<:AbstractTransportAggregation}
    technology_models::Dict # TODO: define strict Type for this
    branch_models::Dict # TODO: Decide name for branches: path? corridors? We are using transport for network

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
    portfolio::PSIP.Portfolio,
    component_type::Type{<:PSIP.Technology},
    investment_formulation::Type{<:InvestmentTechnologyFormulation},
    operations_formulation::Type{<:OperationsTechnologyFormulation},
    feasibility_formulation::Type{<:FeasibilityTechnologyFormulation},
)
    names =
        PSIP.get_name.(PSIP.get_technologies(PSIP.get_available, component_type, portfolio))
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
    portfolio::PSIP.Portfolio,
    model::TechnologyModel{
        T,
        <:InvestmentTechnologyFormulation,
        <:OperationsTechnologyFormulation,
        <:FeasibilityTechnologyFormulation,
    },
) where {T <: PSIP.Technology}
    names = PSIP.get_name.(PSIP.get_technologies(PSIP.get_available, T, portfolio))
    _set_model!(template.technology_models, names, model)
    return
end

function set_technology_model!(
    template::InvestmentModelTemplate,
    names::Vector{String},
    model::TechnologyModel{
        <:PSIP.AggregateTransportTechnology,
        <:InvestmentTechnologyFormulation,
        <:OperationsTechnologyFormulation,
        <:FeasibilityTechnologyFormulation,
    },
)
    _set_model!(template.branch_models, names, model)
    return
end

function get_type_formulation_to_names_map(models_dict::Dict, port::PSIP.Portfolio)
    tech_types = Set()
    capital_formulations = Set()
    operation_formulations = Set()
    feasibility_formulations = Set()
    type_capital_map = Dict()
    type_operation_map = Dict()
    type_feasibility_map = Dict()
    for (model, names) in models_dict
        tech_type = get_technology_type(model)
        cap_formulation = get_investment_formulation(model)
        ops_formulation = get_operations_formulation(model)
        feas_formulation = get_feasibility_formulation(model)
        push!(tech_types, tech_type)
        push!(capital_formulations, cap_formulation)
        push!(operation_formulations, ops_formulation)
        push!(feasibility_formulations, feas_formulation)
        if !haskey(type_capital_map, (tech_type, cap_formulation))
            type_capital_map[(tech_type, cap_formulation)] = deepcopy(names)
        else
            existing_names = type_capital_map[(tech_type, cap_formulation)]
            for name in names
                push!(existing_names, name)
            end
        end
        if !haskey(type_operation_map, (tech_type, ops_formulation))
            type_operation_map[(tech_type, ops_formulation)] = deepcopy(names)
        else
            existing_names = type_operation_map[(tech_type, ops_formulation)]
            for name in names
                push!(existing_names, name)
            end
        end
        if !haskey(type_feasibility_map, (tech_type, feas_formulation))
            type_feasibility_map[(tech_type, feas_formulation)] = deepcopy(names)
        else
            existing_names = type_feasibility_map[(tech_type, feas_formulation)]
            for name in names
                push!(existing_names, name)
            end
        end
    end
    # Remove unavailable names
    all_maps = [type_capital_map, type_operation_map, type_feasibility_map]
    for used_map in all_maps
        for (tuple, existing_names) in used_map
            if isempty(existing_names)
                continue
            end
            ixs_to_delete = Vector{Int}()
            for (ix, name) in enumerate(existing_names)
                tech = PSIP.get_technology(tuple[1], port, name)
                if isnothing(tech)
                    error(
                        "Technology with name $name was added in a Formulation but does not exist in the Portfolio.",
                    )
                end
                if !PSIP.get_available(tech)
                    push!(ixs_to_delete, ix)
                end
            end
            deleteat!(existing_names, ixs_to_delete)
        end
    end
    # Delete empty technologies maps
    for used_map in all_maps
        for (k, v) in used_map
            if isempty(v)
                @info "$k pair has no available technologies"
                pop!(used_map, k)
            end
        end
    end
    return type_capital_map, type_operation_map, type_feasibility_map
end

function names_to_technology_model_map(models_dict::Dict)
    inverse_dic = Dict{String, TechnologyModel}()
    for (model, names) in models_dict
        for name in names
            if haskey(inverse_dic, name)
                error(
                    "Technology $name is currently present in more than one technology model",
                )
            else
                inverse_dic[name] = model
            end
        end
    end
    return inverse_dic
end

function names_to_technology_model_vector(
    names_model_map::Dict{String, TechnologyModel},
    names::Vector{String},
)
    model_vector = Vector{TechnologyModel}(undef, length(names))
    for (ix, name) in enumerate(names)
        model_vector[ix] = names_model_map[name]
    end
    return model_vector
end
