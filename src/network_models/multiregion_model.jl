function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T<:MultiRegionBalanceConstraint,U<:PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_operational_time_steps(time_mapping)
    regions = PSIP.get_regions(PSIP.Zone, port)
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
) where {T<:MultiRegionBalanceFeasibilityConstraint,U<:PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    feas_time_steps = get_feasibility_time_steps(time_mapping)
    op_time_steps = get_operational_time_steps(time_mapping)
    regions = PSIP.get_regions(PSIP.Zone, port)
    expressions = get_expression(container, CapacitySurplus(), U)
    constraint = add_constraints_container!(container, T(), U, regions, feas_time_steps)
    eue = JuMP.@variable(get_jump_model(container), [1:length(regions), 1:length(feas_time_steps)], lower_bound = 0, base_name = "eue")
    # eue_estimate_con = add_constraints_container!(container, EUEEstimateConstraint(), U, regions, time_steps)
    for (op_t, feas_t) in zip(op_time_steps, feas_time_steps), (r_idx, r) in enumerate(regions)
        slope = PSIP.get_ext(r)["slope"]
        intercept = PSIP.get_ext(r)["intercept"]
        constraint[r, feas_t] =
            JuMP.@constraint(get_jump_model(container), expressions[r, feas_t] >= 0)

        for s in 1:length(slope[op_t])
            JuMP.@constraint(
                get_jump_model(container),
                eue[r_idx, op_t] >= intercept[op_t][s] - expressions[r, feas_t] * slope[op_t][s]
            )
        end
    end
    for (r_idx, r) in enumerate(regions)
        max_eue = PSIP.get_ext(r)["max_eue"]
        JuMP.@constraint(
            get_jump_model(container),
            sum(eue[r_idx, :]) <= max_eue
        )
    end

    return
end

# ### Planning Reserve Margin Constraint ####
# function add_constraints!(
#     container::SingleOptimizationContainer,
#     ::Type{T},
#     port::U,
# ) where {T<:PlanningReserveMarginConstraint,U<:PSIP.Portfolio}

#     regions = PSIP.get_regions(PSIP.Zone, port)

#     efc_wind = [v for v in JuMP.all_variables(get_jump_model(container)) if occursin("efc_wind", JuMP.name(v))]
#     efc_pv = [v for v in JuMP.all_variables(get_jump_model(container)) if occursin("efc_pv", JuMP.name(v))]
#     efc_bess = [v for v in JuMP.all_variables(get_jump_model(container)) if occursin("efc_storage", JuMP.name(v))]
#     println(efc_wind, efc_pv, efc_bess)
#     for (r_idx, r) in enumerate(regions)
#         # efc_existing = PSIP.get_ext(r)["efc_existing"]
#         # peak_load = PSIP.get_ext(r)["peak_load"]
#         JuMP.@constraint(
#             get_jump_model(container),
#             # efc_bess[r_idx] + efc_pv[r_idx] + efc_wind[r_idx] >= 1.05 * peak_load - efc_existing
#             efc_bess[r_idx] + efc_pv[r_idx] + efc_wind[r_idx] >= 300.0
#         )
#     end

#     return
# end