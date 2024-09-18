function get_default_time_series_names(
    ::Type{U},
    ::Type{V},
    ::Type{W},
) where {
    U <: PSIP.DemandRequirement,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
}
    return Dict{Type{<:TimeSeriesParameter}, String}()
end

function get_default_attributes(
    ::Type{U},
    ::Type{V},
    ::Type{W},
) where {
    U <: PSIP.DemandRequirement,
    V <: InvestmentTechnologyFormulation,
    W <: OperationsTechnologyFormulation,
}
    return Dict{String, Any}()
end

################### Variables ####################

get_variable_multiplier(::ActivePowerVariable, ::Type{PSIP.DemandRequirement}) = -1.0

################## Expressions ###################

# TODO: SupplyTotal and DemandTotal should probably be defined for each zone/region/etc. later on

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
) where {
    T <: DemandTotal,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.DemandRequirement}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    #expression = get_expression(container, T(), PSIP.Portfolio)

    #TODO: Handle the timeseries in an actual generic way

    # Hard Code Mapping #
    @warn("creating hard code mapping. Remove it later")
    mapping_ops = Dict("2030" => 1:24, "2035" => 25:48)
    mapping_inv = Dict("2030" => 1, "2035" => 2)

    time_steps = get_time_steps(container)

    expression = add_expression_container!(container, expression_type, D, time_steps)

    #TODO: move to separate add_to_expression! function, could not figure out ExpressionKey

    for d in devices
        name = PSIP.get_name(d)
        peak_load = PSIP.get_peak_load(d)
        ts_name = "ops_peak_load"
        ts_keys = filter(x -> x.name == ts_name, IS.get_time_series_keys(d))
        for ts_key in ts_keys
            ts_type = ts_key.time_series_type
            features = ts_key.features
            year = features["year"]
            #rep_day = features["rep_day"]
            ts_data = TimeSeries.values(
                #IS.get_time_series(ts_type, d, ts_name; year=year, rep_day=rep_day).data,
                IS.get_time_series(ts_type, d, ts_name; year=year).data,
            )
            time_steps_ix = mapping_ops[year]
            multiplier = 1.0
            for (ix, t) in enumerate(time_steps_ix)
                _add_to_jump_expression!(
                    expression[t],
                    ts_data[ix] * multiplier,
                )
            end
        end
    end

    return
end

function add_expression!(
    container::SingleOptimizationContainer,
    expression_type::T,
    devices::U,
    formulation::BasicDispatch,
) where {
    T <: SupplyTotal,
    U <: Union{Vector{D}, IS.FlattenIteratorWrapper{D}},
} where {D <: PSIP.DemandRequirement}
    @assert !isempty(devices)
    time_steps = get_time_steps(container)
    #binary = false
    #var = get_variable(container, ActivePowerVariable(), D)

    expression = add_expression_container!(container, expression_type, D, time_steps)

    return
end

################### Constraints ##################

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    #model,
    #::NetworkModel{X},
) where {
    T <: SupplyDemandBalance,
    U <: PSIP.DemandRequirement{PSY.PowerLoad},
    #X <: PM.AbstractPowerModel,
}
    # TODO: Remove technologies from the expression definition for these and add corresponding get_expression functions
    time_steps = get_time_steps(container)

    energy_balance = add_constraints_container!(container, T(), U, time_steps)

    for t in time_steps
        #TODO: Make this generic
        supply = get_expression(container, SupplyTotal(), U)
        demand = get_expression(container, DemandTotal(), U)

        energy_balance[t] =
            JuMP.@constraint(get_jump_model(container), supply - demand >= 0)
    end
end
