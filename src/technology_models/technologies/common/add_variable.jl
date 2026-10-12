#! format: off
# Investment variables are continuous unless the investment formulation is discrete.
get_variable_binary(::InvestmentVariableType, ::PSIP.Technology, ::InvestmentTechnologyFormulation) = false
get_variable_binary(::InvestmentVariableType, ::PSIP.Technology, ::BinaryInvestment) = true
get_variable_integer(::InvestmentVariableType, ::PSIP.Technology, ::InvestmentTechnologyFormulation) = false
get_variable_integer(::InvestmentVariableType, ::PSIP.Technology, ::IntegerInvestment) = true

# Capacity added by one unit of an investment variable.
get_variable_multiplier(::InvestmentVariableType, ::PSIP.Technology, ::InvestmentTechnologyFormulation) = 1.0
#! format: on

"""
Capacity added by one unit of a discrete investment variable. It must be positive, otherwise
the investment would not add any capacity.
"""
function get_unit_size(
    variable_type::InvestmentVariableType,
    d::PSIP.Technology,
    formulation::InvestmentTechnologyFormulation,
)
    unit_size = get_variable_multiplier(variable_type, d, formulation)
    if unit_size <= 0.0
        error(
            "Technology $(PSIP.get_name(d)) needs a positive unit size to be used with " *
            "$(nameof(typeof(formulation))).",
        )
    end
    return unit_size
end

function add_variable!(
    container::SingleOptimizationContainer,
    variable_type::T,
    devices::U,
    formulation::S,
) where {
    T <: InvestmentVariableType,
    S <: InvestmentTechnologyFormulation,
    U <: Vector{D},
} where {D <: PSIP.Technology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(S)
    names = get_variable_names(devices)
    variable = add_variable_container!(
        container,
        variable_type,
        D,
        names,
        time_steps,
        meta=tech_model,
    )
    store_names = get_store_variable_names(get_settings(container))

    for t in time_steps, d in devices, name in get_variable_names(d)
        variable[name, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = store_names ? "$(T)_$(D)_{$(name), $(t)}" : "",
            binary = get_variable_binary(variable_type, d, formulation),
            integer = get_variable_integer(variable_type, d, formulation),
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
    formulation::S,
) where {
    T <: OperationsVariableType,
    S <: OperationsTechnologyFormulation,
    U <: Vector{D},
} where {D <: PSIP.Technology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    names = get_variable_names(devices)

    variable = add_variable_container!(
        container,
        variable_type,
        D,
        names,
        time_steps,
        meta=tech_model,
    )
    store_names = get_store_variable_names(get_settings(container))

    for t in time_steps, d in devices, name in get_variable_names(d)
        variable[name, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = store_names ? "$(T)_$(D)_{$(name), $(t)}" : "",
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
    formulation::S,
) where {
    T <: OperationsVariableType,
    S <: FeasibilityTechnologyFormulation,
    U <: Vector{D},
} where {D <: PSIP.Technology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_feasibility_time_steps(time_mapping)
    tech_model = string(S)

    names = get_variable_names(devices)
    variable = add_variable_container!(
        container,
        variable_type,
        D,
        names,
        time_steps,
        meta=tech_model,
    )
    store_names = get_store_variable_names(get_settings(container))

    for t in time_steps, d in devices, name in get_variable_names(d)
        variable[name, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = store_names ? "$(T)_$(D)_{$(name), $(t)}" : "",
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
    formulation::S,
) where {
    T <: FeasibilityVariableType,
    S <: AbstractTechnologyFormulation,
    U <: Vector{D},
} where {D <: PSIP.Technology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_feasibility_time_steps(time_mapping)
    tech_model = string(S)
    names = get_variable_names(devices)

    variable = add_variable_container!(
        container,
        variable_type,
        D,
        names,
        time_steps,
        meta=tech_model,
    )
    store_names = get_store_variable_names(get_settings(container))

    for t in time_steps, d in devices, name in get_variable_names(d)
        variable[name, t] = JuMP.@variable(
            get_jump_model(container),
            base_name = store_names ? "$(T)_$(D)_{$(name), $(t)}" : "",
        )
        ub = get_variable_upper_bound(variable_type, d, formulation)
        ub !== nothing && JuMP.set_upper_bound(variable[name, t], ub)

        lb = get_variable_lower_bound(variable_type, d, formulation)
        lb !== nothing && JuMP.set_lower_bound(variable[name, t], lb)
    end

    return
end
