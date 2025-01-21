#! format: off

# TODO: Update when storage is updated in portfolios
get_variable_upper_bound(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_upper_bound(::BuildEnergyCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = nothing
get_variable_lower_bound(::BuildEnergyCapacity, d::PSIP.StorageTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_binary(::BuildPowerCapacity, d::PSIP.StorageTechnology, ::ContinuousInvestment) = false

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
    return Dict{String,Any}()
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
        #init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            #init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            sum(var[name, t_p] for t_p in time_steps if t_p <= t),
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
        #init_cap = PSIP.get_initial_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            #init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
            sum(var[name, t_p] for t_p in time_steps if t_p <= t),
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
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveOutPowerVariable,
    W<:SingleRegionBalanceModel,
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
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveInPowerVariable,
    W<:SingleRegionBalanceModel,
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
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
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveOutPowerVariable,
    W<:MultiRegionBalanceModel,
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
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{W},
) where {
    T<:EnergyBalance,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveInPowerVariable,
    W<:MultiRegionBalanceModel,
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
    T<:FeasibilitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveOutPowerVariable,
    W<:SingleRegionBalanceModel,
} where {D<:PSIP.StorageTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(container)
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
    T<:FeasibilitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveInPowerVariable,
    W<:SingleRegionBalanceModel,
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
    T<:FeasibilitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveOutPowerVariable,
    W<:MultiRegionBalanceModel,
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
    T<:FeasibilitySurplus,
    U<:Union{D,Vector{D},IS.FlattenIteratorWrapper{D}},
    V<:ActiveInPowerVariable,
    W<:MultiRegionBalanceModel,
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
    operational_indexes = get_operational_indexes(time_mapping)
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
    operational_indexes = get_operational_indexes(time_mapping)
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
    operational_indexes = get_operational_indexes(time_mapping)
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

    charge = get_variable(container, ActiveInPowerVariable(), D, tech_model)
    discharge = get_variable(container, ActiveOutPowerVariable(), D, tech_model)
    storage_state = get_variable(container, V(), D, tech_model)

    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        if t == 1
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                storage_state[name, t] == charge[name, t] - discharge[name, t]
            )
        else
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                storage_state[name, t] ==
                storage_state[name, t-1] + charge[name, t] - discharge[name, t]
            )
        end
    end
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
        max_capacity = PSIP.get_max_capacity_power(d)
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
        max_capacity = PSIP.get_max_capacity_energy(d)
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
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            #target = PSIP.get_initial_state_of_charge(d) * installed_cap[name, time_step_inv]

            con[name] = JuMP.@constraint(
                get_jump_model(container),
                storage_state[name, time_slices[1]] == 0.0
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

    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)

    for d in devices
        name = PSIP.get_name(d)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            #target = PSIP.get_initial_state_of_charge(d) * installed_cap[name, time_step_inv]
            con[name] = JuMP.@constraint(
                get_jump_model(container),
                storage_state[name, time_slices[end]] == 0.0
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
    formulation::BasicDispatch, #Type{<:PM.AbstractPowerModel},
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
