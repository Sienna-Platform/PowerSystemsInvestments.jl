#! format: off

# TODO: Update when storage is updated in portfolios
get_variable_upper_bound(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_upper_bound(::BuildEnergyCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildEnergyCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_binary(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::ContinuousInvestment) = false


get_variable_upper_bound(::EFCStorage, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::EFCStorage, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = 0.0


get_variable_lower_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::EnergyVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::EnergyVariable, d::PSIP.StorageTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActiveInPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_lower_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActiveOutPowerVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_lower_bound(::EnergyVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::EnergyVariable, d::PSIP.StorageTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_multiplier(::ActiveInPowerVariable, ::Type{PSIP.StorageTechnology}) = 1.0
get_variable_multiplier(::ActiveOutPowerVariable, ::Type{PSIP.StorageTechnology}) = 1.0

#! format: on

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U<:PSIP.StorageTechnology,
    V<:InvestmentTechnologyFormulation,
    W<:OperationsTechnologyFormulation,
    X<:FeasibilityTechnologyFormulation,
}
    return Dict{String,Any}(
        "capacity_credit" => false
    )
end

################### Variables ####################
function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    devices::U,
    formulation::V,
    tech_model::String,
) where {
    T<:InvestmentVariableType,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:IntegerInvestment,
} where {D<:PSIP.StorageTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    binary = false

    names = [PSIP.get_name(d) for d in devices]
    check_duplicate_names(names, container, variable_type, D)

    variable = add_variable_container!(
        container,
        variable_type,
        D,
        names,
        time_steps,
        meta=tech_model,
    )
    for t in time_steps, d in devices
        name = PSY.get_name(d)
        variable[name, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "$(T)_$(D)_{$(name), $(t)}",
            integer = true,
        )
        ub = get_variable_upper_bound(variable_type, d, formulation)
        ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        lb = get_variable_lower_bound(variable_type, d, formulation)
        lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

################## Expressions ###################

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::AbstractTechnologyFormulation,
    tech_model::String,
) where {
    T<:CumulativePowerCapacity,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    binary = false

    var = get_variable(container, BuildPowerCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    # TODO: Move to add_to_expression!
    # TODO: Update with initial capacity once portfolios are updates
    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        init_cap = PSIP.get_existing_cap_power(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            # sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            #binary = binary
        )
        #ub = get_variable_upper_bound(expression_type, d, formulation)
        #ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        #lb = get_variable_lower_bound(expression_type, d, formulation)
        #lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::AbstractTechnologyFormulation,
    tech_model::String,
) where {
    T<:CumulativeEnergyCapacity,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    binary = false

    var = get_variable(container, BuildEnergyCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    # TODO: Move to add_to_expression!
    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        init_cap = PSIP.get_existing_cap_energy(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            # sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            #binary = binary
        )
        #ub = get_variable_upper_bound(expression_type, d, formulation)
        #ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        #lb = get_variable_lower_bound(expression_type, d, formulation)
        #lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
    tech_model::String,
) where {
    T<:CumulativeEnergyCapacity,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:IntegerInvestment,
} where {D<:PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    binary = false

    var = get_variable(container, BuildEnergyCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    for t in time_steps, d in devices
        unit_size = PSIP.get_unit_size_energy(d)
        name = PSIP.get_name(d)
        init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] * unit_size for t_p in time_steps if t_p <= t),
            #binary = binary
        )
        #ub = get_variable_upper_bound(expression_type, d, formulation)
        #ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        #lb = get_variable_lower_bound(expression_type, d, formulation)
        #lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
    tech_model::String,
) where {
    T<:CumulativePowerCapacity,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:IntegerInvestment,
} where {D<:PSIP.SupplyTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    binary = false

    var = get_variable(container, BuildPowerCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    for t in time_steps, d in devices
        unit_size = PSIP.get_unit_size_power(d)
        name = PSIP.get_name(d)
        init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] * unit_size for t_p in time_steps if t_p <= t),
            #binary = binary
        )
        #ub = get_variable_upper_bound(expression_type, d, formulation)
        #ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        #lb = get_variable_lower_bound(expression_type, d, formulation)
        #lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::X,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveOutPowerVariable,
    W<:SingleRegionBalanceModel,
    X<:OperationsTechnologyFormulation
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression["SingleRegion", t],
            variable[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::X,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveInPowerVariable,
    W<:SingleRegionBalanceModel,
    X<:OperationsTechnologyFormulation
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_operational_time_steps(time_mapping)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, V(), D)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression["SingleRegion", t],
            variable[name, t],
            -1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::X,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveOutPowerVariable,
    W<:MultiRegionBalanceModel,
    X<:OperationsTechnologyFormulation
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_operational_time_steps(time_mapping)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        zone = PSIP.get_region(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[zone, t],
            variable[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::X,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveInPowerVariable,
    W<:MultiRegionBalanceModel,
    X<:OperationsTechnologyFormulation
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_operational_time_steps(time_mapping)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        zone = PSIP.get_region(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[zone, t],
            variable[name, t],
            -1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::BasicDispatchFeasibility,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:CapacitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveOutPowerVariable,
    W<:SingleRegionBalanceModel,
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_feasibility_time_steps(container)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression["SingleRegion", t],
            variable[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::BasicDispatchFeasibility,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:CapacitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveInPowerVariable,
    W<:SingleRegionBalanceModel,
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_feasibility_time_steps(time_mapping)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression["SingleRegion", t],
            variable[name, t],
            -1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::BasicDispatchFeasibility,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:CapacitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveOutPowerVariable,
    W<:MultiRegionBalanceModel,
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_feasibility_time_steps(time_mapping)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        zone = PSIP.get_region(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[zone, t],
            variable[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    var::V,
    devices::U,
    formulation::BasicDispatchFeasibility,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:CapacitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveInPowerVariable,
    W<:MultiRegionBalanceModel,
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_feasibility_time_steps(time_mapping)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, V(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        zone = PSIP.get_region(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[zone, t],
            variable[name, t],
            -1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end
#=
function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_steps = get_time_steps(time_mapping)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    expression = get_expression(container, T)

    #TODO: move to separate add_to_expression! function, could not figure out ExpressionKey
    variable = get_variable(container, ActivePowerVariable(), D, tech_model)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[t],
            variable[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end
=#
################### Constraints ##################

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:OutputActivePowerVariableLimitsConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveOutPowerVariable,
} where {D<:PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, CumulativePowerCapacity(), D, tech_model)
    active_power = get_variable(container, V(), D, tech_model)
    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] <= installed_cap[name, time_step_inv]
                )
            end
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:InputActivePowerVariableLimitsConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveInPowerVariable,
} where {D<:PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, CumulativePowerCapacity(), D, tech_model)
    active_power = get_variable(container, V(), D, tech_model)
    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices
        name = PSIP.get_name(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] <= installed_cap[name, time_step_inv]
                )
            end
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:StateofChargeLimitsConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:EnergyVariable,
} where {D<:PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, CumulativeEnergyCapacity(), D, tech_model)
    energy_var = get_variable(container, V(), D, tech_model)
    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    energy_var[name, t] <= installed_cap[name, time_step_inv]
                )
            end
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:EnergyBalanceConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:EnergyVariable,
} where {D<:PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping) #TODO: fix get_time_Steps
    time_steps_op = get_operational_time_steps(time_mapping)
    time_steps_feas = get_feasibility_time_steps(time_mapping)
    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    charge = get_variable(container, ActiveInPowerVariable(), D, tech_model)
    discharge = get_variable(container, ActiveOutPowerVariable(), D, tech_model)
    storage_state = get_variable(container, V(), D, tech_model)
    installed_cap = get_expression(container, CumulativeEnergyCapacity(), D, tech_model)

    operational_indexes = get_operational_indexes(time_mapping)
    feasibility_indexes = get_feasibility_indexes(time_mapping)
    consecutive_slices = get_all_indexes(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        for (t_op, t_feas) in zip(time_steps_op, time_steps_feas)
            # time_slices_op = consecutive_slices[op_ix]
            # time_slices_feas = consecutive_slices[feas_ix]
            # print(time_steps_op, "slice", time_slices_op)
            time_step_inv = inverse_invest_mapping[1]
            initial_state = PSIP.get_initial_state_of_charge(d) * installed_cap[name, time_step_inv]
            # for (t_op, t_feas) in zip(time_slices_op, time_slices_feas)
            if t_op == 1
                con_ub[name, t_op] = JuMP.@constraint(
                    get_jump_model(container),
                    storage_state[name, t_op] == initial_state + charge[name, t_op] - discharge[name, t_op]
                )
                con_ub[name, t_feas] = JuMP.@constraint(
                    get_jump_model(container),
                    storage_state[name, t_feas] == initial_state + charge[name, t_feas] - discharge[name, t_feas]
                )
            else
                con_ub[name, t_op] = JuMP.@constraint(
                    get_jump_model(container),
                    storage_state[name, t_op] ==
                    storage_state[name, t_op-1] + charge[name, t_op] - discharge[name, t_op]
                )
                con_ub[name, t_feas] = JuMP.@constraint(
                    get_jump_model(container),
                    storage_state[name, t_feas] ==
                    storage_state[name, t_feas-1] + charge[name, t_feas] - discharge[name, t_feas]
                )
            end

        end
    end

    # for d in devices, t in time_steps
    #     name = PSIP.get_name(d)

    #     time_slices = consecutive_slices[op_ix]

    #     if t == 1
    #         con_ub[name, t] = JuMP.@constraint(
    #             get_jump_model(container),
    #             storage_state[name, t] == PSIP.charge[name, t] - discharge[name, t]
    #         )
    #     else
    #         con_ub[name, t] = JuMP.@constraint(
    #             get_jump_model(container),
    #             storage_state[name, t] ==
    #             storage_state[name, t-1] + charge[name, t] - discharge[name, t]
    #         )
    #     end
    # end
end

# Maximum cumulative capacity
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:MaximumCumulativePowerCapacity,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:CumulativePowerCapacity,
} where {D<:PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, V(), D, tech_model)

    for d in devices
        name = PSIP.get_name(d)
        max_capacity = PSIP.get_max_cap_power(d)
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity
            )
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:MaximumCumulativeEnergyCapacity,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:CumulativeEnergyCapacity,
    #X <: PM.AbstractPowerModel,
} where {D<:PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, V(), D, tech_model)

    for d in devices
        name = PSIP.get_name(d)
        max_capacity = PSIP.get_max_cap_energy(d)
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity
            )
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:DurationConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:BuildPowerCapacity,
    #X <: PM.AbstractPowerModel,
} where {D<:PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )


    build_power_cap = get_variable(container, BuildPowerCapacity(), D, tech_model)
    build_energy_cap = get_variable(container, BuildEnergyCapacity(), D, tech_model)
    for d in devices
        name = PSIP.get_name(d)
        if PSIP.get_storage_tech(d) == PSY.StorageTech.LIB
            for t in time_steps
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    build_energy_cap[name, t] == 4 * build_power_cap[name, t]
                )
            
            end
        elseif PSIP.get_storage_tech(d) ==  PSY.StorageTech.OTHER_MECH
            for t in time_steps
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    build_energy_cap[name, t] == 10 * build_power_cap[name, t]
                )
            
            end
        end
    end
end

function add_constraints!(
    container::SingleOptimizationContainer,
    p::PSIP.Portfolio,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:StorageCapacityCreditConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:BuildPowerCapacity,
} where {D<:PSIP.StorageTechnology}
    time_mapping = get_time_mapping(container)
    regions = PSIP.get_regions(PSIP.Zone, p)
    installed_cap = get_variable(container, V(), D, tech_model)
    bess_cap = 0.0
    efc = get_variable(container, EFCStorage(), D, tech_model)

    for (r_idx, r) in enumerate(regions)
        efc_region = 0.0
        if haskey(PSIP.get_ext(r), "bess_cc")
            for d in devices
                name = PSIP.get_name(d)
                zone = PSIP.get_region(d)
                if zone == r
                    bess_cap = bess_cap + installed_cap[name, 1]
                    efc_region = efc_region + efc[name, 1]
                end
            end
            bess_cc = PSIP.get_ext(r)["bess_cc"]
            slope = bess_cc[:, 1]
            intercept = bess_cc[:, 2]

            for s in 1:length(slope)
                JuMP.@constraint(
                    get_jump_model(container),
                    efc_region <= bess_cap * slope[s] + intercept[s]
                )
            end
        end
    end
    return
end


function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:InitialStateOfChargeConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:EnergyVariable,
} where {D<:PSIP.StorageTechnology}

    device_names = PSIP.get_name.(devices)
    time_mapping = get_time_mapping(container)
    con = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        meta=tech_model,
    )
    storage_state = get_variable(container, V(), D, tech_model)
    installed_cap = get_expression(container, CumulativeEnergyCapacity(), D, tech_model)

    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_all_indexes(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            target = PSIP.get_initial_state_of_charge(d) * installed_cap[name, time_step_inv]
            initial_state_of_charge = PSIP.get_initial_state_of_charge(d)

            con[name] = JuMP.@constraint(
                get_jump_model(container),
                storage_state[name, time_slices[1]] == target
            )
        end
    end

end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:SparseChrononConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:EnergyVariable,
} where {D<:PSIP.StorageTechnology}
    device_names = PSIP.get_name.(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    storage_state = get_variable(container, V(), D, tech_model)
    installed_cap = get_expression(container, CumulativeEnergyCapacity(), D, tech_model)
    charge = get_variable(container, ActiveInPowerVariable(), D, tech_model)
    discharge = get_variable(container, ActiveOutPowerVariable(), D, tech_model)
    # net_change = get_experssion(container, NetSOCChange(), D, tech_model)
    operational_indexes = get_operational_indexes(time_mapping)
    feasibility_indexes = get_feasibility_indexes(time_mapping)
    all_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        pras_mapping = PSIP.get_ext(d)["pras_tm"]
        num_partition = length(pras_mapping)
        net_change = JuMP.@variable(get_jump_model(container), [1:all_indexes[end]], base_name = "stor_ΔE[$(name)]") #∆e = Pt∈T pt
        net_change_low = JuMP.@variable(get_jump_model(container), [1:all_indexes[end]], base_name = "stor_ΔE_low[$(name)]") #⌊e⌋ variable def for eq1 for each representative day
        net_change_high = JuMP.@variable(get_jump_model(container), [1:all_indexes[end]], base_name = "stor_ΔE_high[$(name)]") # ⌈e⌉ variable def for eq2 for each representative day
        initial_state = JuMP.@variable(get_jump_model(container), [1:num_partition], base_name = "inital_state[$(name)]") # e0p for operation index
        initial_state_feas = JuMP.@variable(get_jump_model(container), [1:num_partition], base_name = "inital_state_feas[$(name)]") # e0p for feasibility index
        for (op_ix, feas_ix) in zip(operational_indexes, feasibility_indexes)
            time_slices_op = consecutive_slices[op_ix]
            time_slices_feas = consecutive_slices[feas_ix]

            JuMP.@constraint(get_jump_model(container), [t in time_slices_op], sum(charge[name, time_slices_op[1]:t]) - sum(discharge[name, time_slices_op[1]:t]) <= net_change_high[op_ix]) # eq1 for operation index

            JuMP.@constraint(get_jump_model(container), [t in time_slices_op], sum(charge[name, time_slices_op[1]:t]) - sum(discharge[name, time_slices_op[1]:t]) >= net_change_low[op_ix]) # eq2 for operation index
            JuMP.@constraint(get_jump_model(container), sum(charge[name, time_slices_op]) - sum(discharge[name, time_slices_op]) == net_change[op_ix]) # definiation of ∆edp for operation index 
            JuMP.@constraint(get_jump_model(container), [t in time_slices_feas], sum(charge[name, time_slices_feas[1]:t]) - sum(discharge[name, time_slices_feas[1]:t]) <= net_change_high[feas_ix]) # eq1 for feasibility index
            JuMP.@constraint(get_jump_model(container), [t in time_slices_feas], sum(charge[name, time_slices_feas[1]:t]) - sum(discharge[name, time_slices_feas[1]:t]) >= net_change_low[feas_ix]) # eq2 for feasibility index
            JuMP.@constraint(get_jump_model(container), sum(charge[name, time_slices_feas]) - sum(discharge[name, time_slices_feas]) == net_change[feas_ix]) # definiation of ∆edp for feasibility index 
        end
        for p_idx = 1:num_partition
            partition = pras_mapping[p_idx]
            op_ix = partition[1]
            feas_ix = op_ix + operational_indexes[end]
            nofdays = partition[2]
            time_step_inv = inverse_invest_mapping[op_ix]
            ### Equation 9 
            if p_idx == 1 ### inital state 
                JuMP.@constraint(
                    get_jump_model(container),
                    initial_state[p_idx] == PSIP.get_initial_state_of_charge(d) * installed_cap[name, time_step_inv])
                JuMP.@constraint(
                    get_jump_model(container),
                    initial_state_feas[p_idx] == PSIP.get_initial_state_of_charge(d) * installed_cap[name, time_step_inv])
            elseif p_idx > 1 && p_idx < num_partition  ### middle stage
                JuMP.@constraint(
                    get_jump_model(container),
                    initial_state[p_idx] == initial_state[p_idx-1] + nofdays * net_change[op_ix])
                JuMP.@constraint(
                    get_jump_model(container),
                    initial_state_feas[p_idx] == initial_state_feas[p_idx-1] + nofdays * net_change[feas_ix])
            else   ### normal transition + end state should be equal to intial state as bondary constraint
                JuMP.@constraint(
                    get_jump_model(container),
                    initial_state[p_idx] == initial_state[p_idx-1] + nofdays * net_change[op_ix])
                JuMP.@constraint(
                    get_jump_model(container),
                    initial_state_feas[p_idx] == initial_state_feas[p_idx-1] + nofdays * net_change[feas_ix])
                JuMP.@constraint(
                    get_jump_model(container),
                    initial_state[p_idx] + nofdays * net_change[op_ix] == PSIP.get_initial_state_of_charge(d) * installed_cap[name, time_step_inv])
                JuMP.@constraint(
                    get_jump_model(container),
                    initial_state_feas[p_idx] + nofdays * initial_state_feas[p_idx-1] == installed_cap[name, time_step_inv])
            end
            ### eq 10-13 for operation index initial_state[p_idx] + 
            JuMP.@constraint(
                get_jump_model(container),
                initial_state[p_idx] + net_change_low[op_ix] >= 0.0) # eq 10
            JuMP.@constraint(
                get_jump_model(container),
                initial_state[p_idx] + net_change_low[op_ix] + (nofdays - 1) * net_change[op_ix] >= 0.0) # eq 11
            JuMP.@constraint(
                get_jump_model(container),
                initial_state[p_idx] + net_change_high[op_ix] <= installed_cap[name, time_step_inv]) # eq 12
            JuMP.@constraint(
                get_jump_model(container),
                initial_state[p_idx] + net_change_high[op_ix] + (nofdays - 1) * net_change[op_ix] <= installed_cap[name, time_step_inv]) # eq 13
            ### eq 10-13 for feasibility index initial_state_feas[p_idx] + 
            JuMP.@constraint(
                get_jump_model(container),
                initial_state_feas[p_idx] + net_change_low[feas_ix] >= 0.0) # eq 10
            JuMP.@constraint(
                get_jump_model(container),
                initial_state_feas[p_idx] + net_change_low[feas_ix] + (nofdays - 1) * net_change[feas_ix] >= 0.0) # eq 11
            JuMP.@constraint(
                get_jump_model(container),
                initial_state_feas[p_idx] + net_change_high[feas_ix] <= installed_cap[name, time_step_inv])  #eq12
            JuMP.@constraint(
                get_jump_model(container),
                initial_state_feas[p_idx] + net_change_high[feas_ix] + (nofdays - 1) * net_change[feas_ix] <= installed_cap[name, time_step_inv]) # eq 13
        end
    end

    return
end


function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
) where {
    T<:StateofChargeTargetConstraint,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:EnergyVariable,
} where {D<:PSIP.StorageTechnology}
    device_names = PSIP.get_name.(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    con = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        meta=tech_model,
    )
    storage_state = get_variable(container, V(), D, tech_model)
    installed_cap = get_expression(container, CumulativeEnergyCapacity(), D, tech_model)

    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            target = PSIP.get_initial_state_of_charge(d) * installed_cap[name, time_step_inv]
            con[name] = JuMP.@constraint(
                get_jump_model(container),
                storage_state[name, time_slices[end]] == target
            )
        end
    end

    return
end


########################### Objective Function Calls#############################################
# These functions are custom implementations of the cost data. In the file objective_functions.jl there are default implementations. Define these only if needed.

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Union{Vector{T},IS.FlattenIteratorWrapper{T}},
    #DeviceModel{T, U},
    formulation::OperationsTechnologyFormulation, #Type{<:PM.AbstractPowerModel},
    tech_model::String,
) where {T<:PSIP.StorageTechnology}#, U <: ActivePowerVariable}
    add_variable_cost!(
        container,
        ActiveOutPowerVariable(),
        devices,
        formulation,
        tech_model,
    )
    add_variable_cost!(container, ActiveInPowerVariable(), devices, formulation, tech_model)
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Union{Vector{T},IS.FlattenIteratorWrapper{T}},
    #DeviceModel{T, U},
    formulation::InvestmentTechnologyFormulation, #Type{<:PM.AbstractPowerModel},
    tech_model::String,
) where {T<:PSIP.StorageTechnology}#, U <: BuildCapacity}
    add_capital_cost!(container, BuildEnergyCapacity(), devices, formulation, tech_model)
    add_capital_cost!(container, BuildPowerCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(container, BuildEnergyCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(container, BuildPowerCapacity(), devices, formulation, tech_model)
    return
end
