#! format: off
get_variable_upper_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_capacity_limits(d).max
get_variable_lower_bound(::BuildCapacity, d::PSIP.SupplyTechnology, ::InvestmentTechnologyFormulation) = PSIP.get_capacity_limits(d).min
get_variable_binary(::BuildCapacity, d::PSIP.SupplyTechnology, ::ContinuousInvestment) = false

get_variable_lower_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::OperationsTechnologyFormulation) = 0.0
get_variable_upper_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::OperationsTechnologyFormulation) = nothing

get_variable_lower_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::BasicDispatchFeasibility) = 0.0
get_variable_upper_bound(::ActivePowerVariable, d::PSIP.SupplyTechnology, ::BasicDispatchFeasibility) = nothing

get_variable_multiplier(_, ::Type{<:PSIP.SupplyTechnology}, ::AbstractTechnologyFormulation) = 1.0
get_expression_multiplier(_, ::Type{<:PSIP.SupplyTechnology}, ::AbstractTechnologyFormulation) = 1.0

get_init_cap(d::PSIP.SupplyTechnology, ::CumulativePowerCapacity, p::PSIP.Portfolio) = PSIP.get_existing_capacity_mw(p, d)

#! format: on

function get_default_time_series_names(::Type{U}) where {U <: PSIP.SupplyTechnology}
    # TODO: We need to discuss about an API for timeseries names for users
    return "ops_variable_cap_factor"
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
    ::Type{X},
) where {
    U <: PSIP.SupplyTechnology,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
    X <: FeasibilityTechnologyFormulation,
}
    return Dict{String, Any}()
end


"""
    get_initial_capacity(d::PSIP.SupplyTechnology{X}, p::PSIP.Portfolio) where {X}

Compute the total nameplate capacity of all existing components of type `X` in the portfolio.

# Arguments
- `d::SupplyTechnology{X}`  
  A supply‐technology descriptor which may carry an `ExistingCapacity` supplemental attribute listing technology names.
- `p::Portfolio`  
  The portfolio whose `base_system` holds the actual component instances.

# Returns
- `Float64`  
  The sum of `PSY.get_rating(component)` over every component of type `X` whose `name` appears in the technology list.  

# Notes
- If there is not exactly one `ExistingCapacity` attribute, or if it lists no technologies, or if the system has no `X` components, the function issues a warning and returns `0.0`.  
"""
function get_initial_capacity(d::PSIP.SupplyTechnology{X}, p::PSIP.Portfolio) where {X}
    """ 
    Attempt to retrieve an ExistingCapacity Supplemental Attribute, if its empty, then return 0.0.
    If there is ExistingCapacity supplemental attribute, maybe check that is unique and error if there is more than 1?
    Now if there is only one, check the existing_technologies field. If it's empty, give a warning that there exists an existing capacity attribute but nothing is there, and return 0.0.
    You can retrieve the base system from the portfolio doing sys = p.base_system
    With X, you can retrieve components from the system doing PSY.get_components(X, sys)
    If is empty the components, then a give warning, that the system does not have any component of type X and return 0.0.
    If is not empty, then filter the components by the name in the existingcapacity attribute and return the sum of the rating of the components. Do some checks here
    """

    try 
        # pull out any ExistingCapacity attributes
        attrs = IS.get_supplemental_attributes(PSIP.ExistingCapacity, d)
    catch e
        @error(
            "ExistingCapacity attribute not found. Please check the attribute name."
        )
        return 0.0
    end

    attrs = IS.get_supplemental_attributes(PSIP.ExistingCapacity, d)
    
    if length(attrs) != 1
        @warn length(attrs) > 1 ? 
            "Multiple ExistingCapacity attributes – returning 0.0" :
            "No ExistingCapacity attribute – returning 0.0"
        return 0.0
    end

    techs = attrs[1].existing_technologies
    isempty(techs) && (
        @warn "ExistingCapacity has no listed technologies – returning 0.0"; 
        return 0.0
    )

    comps = PSY.get_components(X, p.base_system)
    isempty(comps) && (
        @warn "No components of type $X in system – returning 0.0"; 
        return 0.0
    )

    # TODO: Rodrigo review whether building a Set for fast name‐membership tests is the direction we want
    tech_set = Set(techs)

    # filter out just the components whose name is declared
    matched = [c for c in comps if c.name in tech_set]

    # Check 1) if nothing matched at all, warn & exit
    if isempty(matched)
        @warn "No components matching any of $(collect(tech_set)) in the system – returning 0.0"
        return 0.0
    end

    # Check 2) if some declared names didn't correspond to any component, warn about the missing ones
    found_names = Set(c.name for c in matched)
    missing     = setdiff(tech_set, found_names)
    if !isempty(missing)
        @warn "Declared technologies not found in system components: $(collect(missing))"
    end

    # return sum up the ratings of all matched components
    return sum(PSY.get_rating(c) for c in matched)
end


################### Variables ####################

################## Expressions ###################

function add_expression!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: CumulativeCapacity,
    U <: Vector{D},
    V <: ContinuousInvestment,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

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
        init_cap = get_initial_capacity(d, portfolio)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] for t_p in time_steps if t_p <= t),
        )
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: CumulativeCapacity,
    U <: Vector{D},
    V <: IntegerInvestment,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(V)

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
        unit_size = PSIP.get_unit_size(d)
        name = PSIP.get_name(d)
        init_cap = get_initial_capacity(d, portfolio)
        expression[name, t] = JuMP.@expression(
            get_jump_model(container),
            init_cap + sum(var[name, t_p] * unit_size for t_p in time_steps if t_p <= t),
        )
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::V,
) where {
    T <: VariableOMCost,
    U <: Vector{D},
    V <: AbstractTechnologyFormulation,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(V)

    add_expression_container!(
        container,
        expression_type,
        D,
        [PSIP.get_name(d) for d in devices],
        time_steps,
        meta=tech_model,
    )

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: BasicDispatch,
    T <: EnergyBalance,
    U <: Vector{D},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    W = ActivePowerVariable
    variable = get_variable(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        _add_to_jump_expression!(
            expression[SINGLE_REGION, t],
            variable[name, t],
            get_variable_multiplier(W(), D, S()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: BasicDispatch,
    T <: EnergyBalance,
    U <: Vector{D},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)

    W = ActivePowerVariable
    variable = get_variable(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)
    for d in devices, t in time_steps
        name = PSIP.get_name(d)
        # Only 1 region supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
        _add_to_jump_expression!(
            expression[region, t],
            variable[name, t],
            get_variable_multiplier(W(), D, S()),
        )
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: SingleRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    tech_model = string(S)

    W = CumulativeCapacity
    installed_cap = get_expression(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    feasibility_indexes = get_feasibility_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices
        name = PSIP.get_name(d)
        for op_ix in feasibility_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                _add_to_jump_expression!(
                    expression[SINGLE_REGION, t],
                    installed_cap[name, time_step_inv],
                    get_expression_multiplier(W(), D, S()),
                )
            end
        end
    end

    return
end

function add_to_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::S,
    transport_model::TransportModel{V},
) where {
    S <: BasicDispatchFeasibility,
    T <: FeasibilitySurplus,
    U <: Vector{D},
    V <: MultiRegionBalanceModel,
} where {D <: PSIP.SupplyTechnology}
    @assert !isempty(devices)
    time_mapping = get_time_mapping(container)
    tech_model = string(S)

    W = CumulativeCapacity
    installed_cap = get_expression(container, W(), D, tech_model)
    expression = get_expression(container, T(), PSIP.Portfolio)

    feasibility_indexes = get_feasibility_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    for d in devices
        name = PSIP.get_name(d)
        # Only 1 region supported
        region = PSIP.get_name(only(PSIP.get_region(d)))
        for op_ix in feasibility_indexes
            time_slices = consecutive_slices[op_ix]
            time_step_inv = inverse_invest_mapping[op_ix]
            for t in time_slices
                _add_to_jump_expression!(
                    expression[region, t],
                    installed_cap[name, time_step_inv],
                    get_expression_multiplier(W(), D, S()),
                )
            end
        end
    end

    return
end
################### Constraints ##################

# Limits for renewables #
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Vector{D},
    V <: ActivePowerVariable,
    S <: BasicDispatch,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.RenewableDispatch}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
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
    operational_indexes = get_all_indexes(time_mapping)
    consecutive_slices = get_consecutive_slices(time_mapping)
    inverse_invest_mapping = get_inverse_invest_mapping(time_mapping)
    time_stamps = get_time_stamps(time_mapping)

    for (ix, d) in enumerate(devices)
        name = PSIP.get_name(d)
        tech_model = tech_model_vector[ix]
        inv_model = string(get_investment_formulation(tech_model))
        installed_cap = get_expression(container, CumulativeCapacity(), D, inv_model)
        for op_ix in operational_indexes
            time_slices = consecutive_slices[op_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            ts_data = TimeSeries.values(time_series.data)
            first_tstamp = time_stamps[first(time_slices)]
            first_ts_tstamp = first(TimeSeries.timestamp(time_series.data))
            if first_tstamp != first_ts_tstamp
                @error(
                    "Initial timestamp of timeseries $(IS.get_name(time_series)) of technology $name does not match with the expected representative day $op_ix"
                )
            end
            time_step_inv = inverse_invest_mapping[op_ix]
            for (ix, t) in enumerate(time_slices)
                con_ub[name, t] = JuMP.@constraint(
                    get_jump_model(container),
                    active_power[name, t] <=
                    ts_data[ix] * installed_cap[name, time_step_inv]
                )
            end
        end
    end
    return
end

# Limits for thermals #
function add_constraints!(
    container::SingleOptimizationContainer,
    ::T,
    ::V,
    devices::U,
    formulation::S,
    tech_model_vector::Vector{X},
) where {
    T <: ActivePowerLimitsConstraint,
    U <: Vector{D},
    V <: ActivePowerVariable,
    S <: BasicDispatch,
    X <: TechnologyModel,
} where {D <: PSIP.SupplyTechnology{PSY.ThermalStandard}}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    tech_model = string(S)
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
    operational_indexes = get_all_indexes(time_mapping)
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
    formulation::S,
) where {
    T <: MaximumCumulativeCapacity,
    S <: InvestmentTechnologyFormulation,
    U <: Vector{D},
    V <: CumulativeCapacity,
} where {D <: PSIP.SupplyTechnology}
    time_mapping = get_time_mapping(container)
    time_steps = get_investment_time_steps(time_mapping)
    tech_model = string(S)

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
        max_capacity = PSIP.get_capacity_limits(d).max
        for t in time_steps
            con_ub[name, t] = JuMP.@constraint(
                get_jump_model(container),
                installed_cap[name, t] <= max_capacity
            )
        end
    end
end

########################### Objective Function Calls#############################################
# These functions are custom implementations of the cost data. In the file objective_functions.jl there are default implementations. Define these only if needed.

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::S,
) where {T <: PSIP.SupplyTechnology, S <: BasicDispatch}
    tech_model = string(S)
    add_variable_cost!(container, ActivePowerVariable(), devices, formulation, tech_model)
    return
end

function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::B,
) where {T <: PSIP.SupplyTechnology, B <: InvestmentTechnologyFormulation}
    tech_model = string(B)
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    add_fixed_om_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    return
end
function objective_function!(
    container::SingleOptimizationContainer,
    devices::Vector{T},
    formulation::B,
) where {
    T <: PSIP.SupplyTechnology{PSIP.RenewableDispatch},
    B <: InvestmentTechnologyFormulation,
}
    tech_model = string(B)
    add_capital_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    #TODO: Add fixed_om costs for renewables (RenewableGenerationCost does not have fixed cost component?)
    # add_fixed_om_cost!(container, BuildCapacity(), devices, formulation, tech_model)
    return
end
