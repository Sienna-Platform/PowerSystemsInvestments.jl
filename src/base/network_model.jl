function _check_pm_formulation(::Type{T}) where {T <: PM.AbstractPowerModel}
    if !isconcretetype(T)
        throw(
            ArgumentError(
                "The network model must contain only concrete types, $(T) is an Abstract Type",
            ),
        )
    end
end

mutable struct NetworkModel{T <: PM.AbstractPowerModel}
    use_slacks::Bool
    PTDF_matrix::Union{Nothing, PNM.PowerNetworkMatrix}
    subnetworks::Dict{Int, Set{Int}}
    bus_area_map::Dict{PSY.ACBus, Int}
    duals::Vector{DataType}
    subsystem::Union{Nothing, String}
    modeled_branch_types::Vector{DataType}

    function NetworkModel(
        ::Type{T};
        use_slacks=false,
        PTDF_matrix=nothing,
        subnetworks=Dict{Int, Set{Int}}(),
        duals=Vector{DataType}(),
    ) where {T <: PM.AbstractPowerModel}
        _check_pm_formulation(T)
        new{T}(
            use_slacks,
            PTDF_matrix,
            subnetworks,
            Dict{PSY.ACBus, Int}(),
            duals,
            nothing,
            Vector{DataType}(),
        )
    end
end

get_use_slacks(m::NetworkModel) = m.use_slacks
get_PTDF_matrix(m::NetworkModel) = m.PTDF_matrix
get_duals(m::NetworkModel) = m.duals
get_network_formulation(::NetworkModel{T}) where {T} = T

function instantiate_network_model(::NetworkModel{CopperPlatePowerModel}, ::PSIP.Portfolio)
    #=
    if isempty(model.subnetworks)
        model.subnetworks = PNM.find_subnetworks(sys)
    end

    if length(model.subnetworks) > 1
        @debug "System Contains Multiple Subnetworks. Assigning buses to subnetworks."
        _assign_subnetworks_to_buses(model, sys)
    end
    =#
    return
end
