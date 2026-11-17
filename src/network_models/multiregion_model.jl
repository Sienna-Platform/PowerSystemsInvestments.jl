function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: MultiRegionBalanceConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    regions = PSIP.get_name.(PSIP.get_regions(PSIP.Zone, port))
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
) where {T <: MultiRegionBalanceFeasibilityConstraint, U <: PSIP.Portfolio}
    regions = PSIP.get_name.(PSIP.get_regions(PSIP.Zone, port))
    _add_feasibility_constraints!(container, T, U, regions)
    return
end

# In the feasibility periods each region covers its demand with the capacity installed in it
# and the capacity it can import over its branches. The system as a whole must cover its
# demand with installed capacity, so that the same branch capacity does not serve both of its
# ends.
function _add_feasibility_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    ::Type{U},
    regions::Vector{String},
) where {T <: ISOPT.ConstraintType, U <: PSIP.Portfolio}
    time_steps = get_time_steps(get_time_mapping(container))
    feasibility_time_steps = get_feasibility_time_steps(get_time_mapping(container))
    surplus = get_expression(container, FeasibilitySurplus(), U)
    imports = get_expression(container, FeasibilityImportCapacity(), U)
    constraint = add_constraints_container!(container, T(), U, regions, time_steps)
    for t in time_steps, r in regions
        constraint[r, t] =
            JuMP.@constraint(get_jump_model(container), surplus[r, t] + imports[r, t] >= 0)
    end
    system_constraint =
        add_constraints_container!(container, T(), U, feasibility_time_steps, meta="system")
    for t in feasibility_time_steps
        system_constraint[t] = JuMP.@constraint(
            get_jump_model(container),
            sum(surplus[r, t] for r in regions) >= 0
        )
    end
    return
end
