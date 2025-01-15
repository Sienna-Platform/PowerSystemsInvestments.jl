function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    regions::U,
) where {
    T <: OperationsVariableType,
    U <: Union{D, Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.Region}
    #@assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    binary = false

    #names = [PSIP.get_name(d) for d in devices]
    variable = add_variable_container!(
        container,
        variable_type,
        D,
        regions,
        time_steps,
    )

    for r in regions, t in time_steps
        name = PSIP.get_name(r)
        variable[r, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "$(T)_$(D)_{$(name), $(t)}",
            binary = binary
        )
    end

    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: NodalBalanceConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    regions = PSIP.get_regions(PSIP.Bus, port)
    expressions = get_expression(container, EnergyBalance(), U)
    constraint = add_constraints_container!(container, T(), U, regions, time_steps)
    for t in time_steps, r in regions
        constraint[r, t] =
            JuMP.@constraint(get_jump_model(container), expressions[r, t] == 0)
    end

    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: ReferenceBusConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    regions = PSIP.get_regions(PSIP.Bus, port)

    variable = get_variable(container, VoltageAngle(), PSIP.Bus)
    constraint = add_constraints_container!(container, T(), U, regions, time_steps)
    for t in time_steps, r in regions
        bustype = PSIP.get_bustype(r)
        if !isnothing(bustype)
            if bustype == PSY.ACBusTypes.REF
                constraint[r, t] =
                    JuMP.@constraint(get_jump_model(container), variable[r, t] == 0)
            end
        end
    end

    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: AngleLimitsConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    regions = PSIP.get_regions(PSIP.Bus, port)

    variable = get_variable(container, VoltageAngle(), PSIP.Bus)
    constraint = add_constraints_container!(container, T(), U, regions, time_steps)
    for t in time_steps, r in regions
        angle_limit = PSIP.get_angle_limit(r)
        constraint[r, t] = JuMP.@constraint(
                get_jump_model(container), 
                -1.0*angle_limit <= variable[r, t] <= angle_limit
        )
    end

    return
end