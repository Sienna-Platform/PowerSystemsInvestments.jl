#! format: off
get_variable_upper_bound(::BuildCapacity, d::GenericTransportTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_maximum_new_capacity(d)
get_variable_lower_bound(::BuildCapacity, d::GenericTransportTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_binary(::BuildCapacity, d::GenericTransportTechnology, ::ContinuousInvestment) = false

get_variable_lower_bound(::ActivePowerVariable, d::GenericTransportTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActivePowerVariable, d::GenericTransportTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_multiplier(::ActivePowerVariable, ::Type{GenericTransportTechnology}) = 1.0

#! format: on

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U <: GenericTransportTechnology,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
    X <: FeasibilityTechnologyFormulation,
}
    return Dict{String, Any}()
end

################### Variables ####################

################## Expressions ###################

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::AbstractTechnologyFormulation,
    tech_model::String,
    transport_model::TransportModel{V},
) where {
    T <: CumulativeCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: AbstractTransportAggregation,
} where {D <: GenericTransportTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    binary = false

    var = get_variable(container, BuildCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    # TODO: Move to add_to_expression?
    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        init_cap = PSIP.get_existing_line_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
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
    transport_model::TransportModel{V},
) where {
    T <: LineFlow,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: AbstractTransportAggregation,
} where {D <: GenericTransportTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    binary = false

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    angles = get_variable(container, VoltageAngle(), PSIP.Bus)
    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        
        susceptance = PSIP.get_susceptance(d)
        start_region = PSIP.get_start_region(d)
        end_region = PSIP.get_end_region(d)

        angle_from = angles[start_region, t]
        angle_to = angles[end_region, t]
        
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            susceptance*(angle_from-angle_to),
            #binary = binary
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: SingleRegionBalanceModel,
} where {D <: GenericTransportTechnology}
    # Do nothing
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
    tech_model::String,
    transport_model::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: MultiRegionBalanceModel,
} where {D <: GenericTransportTechnology}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    variable = get_variable(container, ActivePowerVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    # expression = add_expression_container!(container, expression_type, D, time_steps)
    # Assuming that energy travels from start to end, so if dispatch of Branch is positive, it is subtracted from start_region
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        start_region = PSIP.get_start_region(d)
        end_region = PSIP.get_end_region(d)
        losses = PSIP.get_line_loss(d)
        #bus_no = PNM.get_mapped_bus_number(radial_network_reduction, PSY.get_bus(d))
        _add_to_jump_expression!(
            expression[start_region, t],
            variable[name, t],
            -1.0, #get_variable_multiplier(U(), V, W()),
        )
        _add_to_jump_expression!(
            expression[end_region, t],
            variable[name, t],
            (1.0 - losses), #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicPowerFlow,
    tech_model::String,
    transport_model::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: NodalBalanceModel,
} where {D <: GenericTransportTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

    expression = get_expression(container, T(), PSIP.Portfolio)
    line_flow = get_expression(container, LineFlow(), D, tech_model)

    # Assuming that energy travels from start to end, so if dispatch of Branch is positive, it is subtracted from start_region
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        susceptance = PSIP.get_susceptance(d)
        start_region = PSIP.get_start_region(d)
        end_region = PSIP.get_end_region(d)
        
        _add_to_jump_expression!(
            expression[start_region, t],
            line_flow[name, t],
            -1.0, #get_variable_multiplier(U(), V, W()),
        )
        _add_to_jump_expression!(
            expression[end_region, t],
            line_flow[name, t],
            1.0, #get_variable_multiplier(U(), V, W()),
        )
    end

    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    tech_model::String,
    transport_model::TransportModel{V},
) where {
    T <: PowerFlowLimitsConstraint,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: NodalBalanceModel,
} where {D <: GenericTransportTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

    device_names = PSIP.get_name.(devices)
    con_lb = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model*"_lb",
    )
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model*"_ub",
    )

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)
    line_flow = get_expression(container, LineFlow(), D, tech_model)
    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    time_stamps = get_time_stamps(time_mapping)
    for d in devices
        name = PSIP.get_name(d)
        
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices

                con_lb[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    -1.0*installed_cap[name, time_step_inv] <= line_flow[name, t]
                )

                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    line_flow[name, t] <= installed_cap[name, time_step_inv]
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
    transport_model::TransportModel{X},
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: ActivePowerVariable,
    X <: AbstractTransportAggregation,
} where {D <: GenericTransportTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    # Hard Code Mapping #

    device_names = PSIP.get_name.(devices)
    con_ub = add_constraints_container!(
        container,
        T(),
        D,
        device_names,
        time_steps,
        meta=tech_model,
    )

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)
    active_power = get_variable(container, V(), D, tech_model)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    time_stamps = get_time_stamps(time_mapping)
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
    return
end

# Maximum cumulative capacity
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
    transport_model::TransportModel{X},
) where {
    T <: MaximumCumulativeCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: CumulativeCapacity,
    X <: AbstractTransportAggregation,
} where {D <: GenericTransportTechnology}
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

    installed_cap = get_expression(container, CumulativeCapacity(), D, tech_model)

    for d in devices
        name = PSIP.get_name(d)
        max_capacity = PSIP.get_maximum_new_capacity(d)
        init_cap = PSIP.get_existing_line_capacity(d)
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity + init_cap
            )
        end
    end
end

########################### Objective Function Calls#############################################
function objective_function!(
    container::SingleOptimizationContainer,
    devices::Union{Vector{T}, IS.FlattenIteratorWrapper{T}},
    #DeviceModel{T, U},
    formulation::ContinuousInvestment, #Type{<:PM.AbstractPowerModel},
    tech_model::String,
) where {T <: GenericTransportTechnology}#, U <: BuildCapacity}
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model) #U()
    #add_fixed_om_cost!(container, CumulativeCapacity(), devices, formulation, tech_model)
    return
end
