function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    devices::U,
    formulation::AbstractTechnologyFormulation,
) where {
    T <: InvestmentVariableType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.Technology}
    @assert !isempty(devices)
    time_steps = get_time_steps_investments(container)
    binary = false

    variable = add_variable_container!(
        container,
        variable_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
    )

    for t in time_steps, d in devices
        name = PSY.get_name(d)
        variable[name, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "$(T)_$(D)_{$(name), $(t)}",
            binary = binary
        )
        ub = get_variable_upper_bound(variable_type, d, formulation)
        ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        lb = get_variable_lower_bound(variable_type, d, formulation)
        lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end

function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    devices::U,
    formulation::AbstractTechnologyFormulation,
) where {
    T <: OperationsVariableType,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.Technology}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    binary = false

    variable = add_variable_container!(
        container,
        variable_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
    )

    for t in time_steps, d in devices
        name = PSY.get_name(d)
        variable[name, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = "$(T)_$(D)_{$(name), $(t)}",
            binary = binary
        )
        ub = get_variable_upper_bound(variable_type, d, formulation)
        ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        lb = get_variable_lower_bound(variable_type, d, formulation)
        lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end
