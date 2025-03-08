#! format: off
get_variable_upper_bound(::BuildCapacity, d::GenericTransportTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_maximum_new_capacity(d)
get_variable_lower_bound(::BuildCapacity, d::GenericTransportTechnology, ::InvestmentTechnologyFormulation) = 0.0
get_variable_binary(::BuildCapacity, d::GenericTransportTechnology, ::ContinuousInvestment) = false

get_variable_lower_bound(::FlowActivePowerVariable, d::GenericTransportTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::FlowActivePowerVariable, d::GenericTransportTechnology, ::OperationsTechnologyFormulation) = nothing

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
) where {
    T <: CumulativeCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: GenericTransportTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)

    var = get_variable(container, BuildCapacity(), D, tech_model)

    expression = add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    for t in time_steps, d in devices
        name = PSIP.get_name(d)
        init_cap = PSIP.get_existing_line_capacity(d)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
        )
    end

    return
end

function add_to_expression!(
    ::SingleOptimizationContainer,
    ::T,
    ::U,
    ::BasicDispatch,
    ::String,
    ::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: SingleRegionBalanceModel,
} where {D <: GenericTransportTechnology}
    # Do nothing for Transport Paths in SingleRegion models
    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    ::T,
    devices::U,
    ::BasicDispatch,
    tech_model::String,
    ::TransportModel{V},
) where {
    T <: EnergyBalance,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: MultiRegionBalanceModel,
} where {D <: GenericTransportTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)

    variable = get_variable(container, FlowActivePowerVariable(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    # Assuming that energy travels from start to end, so if dispatch of Branch is positive, it is subtracted from start_region
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        start_region = PSIP.get_start_region(d)
        end_region = PSIP.get_end_region(d)
        losses = PSIP.get_line_loss(d)
        _add_to_jump_expression!(expression[start_region, t], variable[name, t], -1.0)
        _add_to_jump_expression!(
            expression[end_region, t],
            variable[name, t],
            (1.0 - losses), # Losses are assumed in the end region
        )
    end

    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    tech_model::String,
    tech_model_vector::Vector{TechnologyModel},
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: FlowActivePowerVariable,
} where {D <: GenericTransportTechnology}
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

    active_power = get_variable(container, V(), D, tech_model)
    operational_indexes = get_operational_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        tech_model = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
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
) where {
    T <: MaximumCumulativeCapacity,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
    V <: CumulativeCapacity,
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
    formulation::ContinuousInvestment,
    tech_model::String,
) where {T <: GenericTransportTechnology}
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    # TODO: Decide if we want to include fixed OM cost for Transport Paths
    #add_fixed_om_cost!(container, CumulativeCapacity(), devices, formulation, tech_model)
    return
end
