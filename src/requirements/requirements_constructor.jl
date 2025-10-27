function construct_requirements!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    names::Vector{String},
    ::ArgumentConstructStage,
    ::CapitalCostModel,
    tech_type::Type{T},
    tech_formulation::Type{B},
    transport_model::TransportModel{<:AbstractTransportAggregation},
    tech_model_vector::Vector{X},
) where {T <: PSIP.SupplyTechnology, B <: EnergyShareRequirementModel, X <: TechnologyModel}
    # TODO: decide arguments of the function and implementation for EnergyShareRequirementModel
    devices = [PSIP.get_technology(T, p, n) for n in names]

    add_variable!(container, BuildCapacity(), devices, B())

    add_expression!(container, p, CumulativeCapacity(), devices, B())
    return
end

#=
function construct_services!(
    container::OptimizationContainer,
    sys::PSY.System,
    stage::ArgumentConstructStage,
    services_template::ServicesModelContainer,
    devices_template::DevicesModelContainer,
    network_model::NetworkModel{<:PM.AbstractPowerModel},
)
    isempty(services_template) && return
    incompatible_device_types = get_incompatible_devices(devices_template)

    groupservice = nothing

    for (key, service_model) in services_template
        if get_formulation(service_model) === GroupReserve  # group service needs to be constructed last
            groupservice = key
            continue
        end
        isempty(get_contributing_devices(service_model)) && continue
        construct_service!(
            container,
            sys,
            stage,
            service_model,
            devices_template,
            incompatible_device_types,
            network_model,
        )
    end
    groupservice === nothing || construct_service!(
        container,
        sys,
        stage,
        services_template[groupservice],
        devices_template,
        incompatible_device_types,
        network_model,
    )
    return
end
=#
