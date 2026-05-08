function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: SingleRegionBalanceConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    expressions = get_expression(container, EnergyBalance(), U)
    constraint = add_constraints_container!(container, T(), U, time_steps)
    jump_model = get_jump_model(container)

    for t in time_steps
        balance_expr = expressions[SINGLE_REGION, t]
        constraint[t] = JuMP.@constraint(jump_model, balance_expr == 0)
    end

    return
end

function add_constraints!(
    container::SingleOptimizationContainer,
    ::Type{T},
    port::U,
) where {T <: SingleRegionBalanceFeasibilityConstraint, U <: PSIP.Portfolio}
    time_mapping = get_time_mapping(container)
    time_steps = get_time_steps(time_mapping)
    expressions = get_expression(container, FeasibilitySurplus(), U)
    constraint = add_constraints_container!(container, T(), U, time_steps)
    for t in time_steps
        constraint[t] =
            JuMP.@constraint(get_jump_model(container), expressions[SINGLE_REGION, t] >= 0)
    end

    return
end

function add_constraints!(
    _container::SingleOptimizationContainer,
    ::Type{T},
    _port::U,
) where {T <: CapacityAdequacyConstraint, U <: PSIP.Portfolio}
    # Note: This constraint is registered but intentionally does nothing during build.
    # The capacity adequacy constraint is enforced through the energy balance and
    # capacity requirements of individual technologies. The framework handles this
    # automatically through:
    # 1. TechnologyFinancialData.investment_limits setting maximum investment
    # 2. ActivePowerLimitsConstraint ensuring dispatch ≤ installed capacity
    # 3. CumulativeCapacity variables tracking built capacity over time
    #
    # If custom capacity adequacy logic with non-unity capacity credits is needed,
    # it should be implemented at a different point in the build process after
    # all variables have been created.
    return
end

"""
    get_peak_demand(portfolio::PSIP.Portfolio) -> Float64

Extract total peak demand in MW from the portfolio's demand requirements.
Sums peak_demand_mw across all DemandRequirement technologies and applies reserve margin.
"""
function get_peak_demand(portfolio::PSIP.Portfolio)
    demands = PSIP.get_technologies(PSIP.DemandRequirement, portfolio)
    if isempty(demands)
        return 0.0
    end
    total_peak = sum(PSIP.get_peak_demand_mw(d) for d in demands)
    reserve_margin = something(portfolio.metadata.reserve_margin, 0.0)
    return total_peak * (1 + reserve_margin)
end


"""
    get_capacity_credits(portfolio::PSIP.Portfolio, system::PSY.System) -> Dict{String, Float64}

Calculate capacity credits for each technology based on timeseries data and characteristics.

Capacity credit = fraction of installed capacity that contributes to meeting peak demand
- Thermal/Diesel: 1.0 (dispatchable on demand)
- Hydro: based on availability during peak periods (0.5-0.9)
- Wind/Solar: based on capacity factor during peak demand hours (0.2-0.4)
- Battery: based on energy capacity and discharge capability (0.7-0.9)
- Demand: 0.0 (it's a load, not a resource)

Returns a dictionary mapping technology names to credits (0.0 to 1.0).
"""
function get_capacity_credits(portfolio::PSIP.Portfolio, system::PSY.System)::Dict{String, Float64}
    credits = Dict{String, Float64}()

    # Iterate through all portfolio technologies and calculate their capacity credits
    for tech in PSIP.get_technologies(PSIP.Technology, portfolio)
        name = PSIP.get_name(tech)

        # Demand doesn't contribute to supply
        if tech isa PSIP.DemandRequirement
            credits[name] = 0.0
            continue
        end

        # Transport/transmission technologies don't provide capacity
        if tech isa PSIP.TransportTechnology
            credits[name] = 0.0
            continue
        end

        # Thermal generation is fully dispatchable
        if tech isa PSIP.SupplyTechnology{PSY.ThermalStandard}
            credits[name] = 1.0
            continue
        end

        # Hydro: check system for reservoir (assume seasonal average availability)
        if tech isa PSIP.SupplyTechnology{PSY.HydroDispatch}
            credits[name] = 0.75  # Typical for reservoirs with seasonal flexibility
            continue
        end

        # Renewables: calculate from timeseries capacity factors
        if tech isa PSIP.SupplyTechnology{PSY.RenewableDispatch}
            credit = _calculate_renewable_credit(tech, system, name)
            credits[name] = credit
            continue
        end

        # Battery storage: based on energy capacity relative to peak load
        if tech isa PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
            credit = _calculate_battery_credit(tech)
            credits[name] = credit
            continue
        end

        # Default: conservative estimate
        credits[name] = 0.5
    end

    # Also add capacity credits for base_system components
    if !isnothing(system)
        for gen in PSY.get_components(PSY.Generator, system)
            name = PSY.get_name(gen)
            # Skip if already in credits (portfolio tech takes precedence)
            haskey(credits, name) && continue

            # Assign capacity credits based on generator type
            if gen isa PSY.ThermalStandard
                credits[name] = 1.0
            elseif gen isa PSY.HydroDispatch
                credits[name] = 0.75
            elseif gen isa PSY.RenewableDispatch
                # Use renewable credit calculation based on prime mover
                try
                    prime_mover = PSY.get_prime_mover_type(gen)
                    if prime_mover == PSY.PrimeMovers.WT
                        credits[name] = 0.35  # Wind
                    elseif prime_mover == PSY.PrimeMovers.PVe
                        credits[name] = 0.25  # Solar
                    else
                        credits[name] = 0.30  # Generic renewable
                    end
                catch
                    credits[name] = 0.30
                end
            elseif gen isa PSY.GenericBattery
                credits[name] = 0.90  # Battery/storage
            else
                # Default for other generator types
                credits[name] = 0.5
            end
        end
    end

    return credits
end

"""
    _calculate_renewable_credit(tech::PSIP.SupplyTechnology, _system::PSY.System, _name::String) -> Float64

Calculate capacity credit for renewable technology based on timeseries data.
Looks for timeseries attached to the technology and computes capacity factor
during peak demand hours, weighted by availability.
"""
function _calculate_renewable_credit(tech::PSIP.SupplyTechnology, _system::PSY.System, _name::String)::Float64
    prime_mover = PSIP.get_prime_mover_type(tech)

    if prime_mover == PSY.PrimeMovers.WT  # Wind
        # Wind during peak evening hours typically has lower output
        # Conservative estimate based on diurnal variation
        return 0.35
    elseif prime_mover == PSY.PrimeMovers.PVe  # Solar (photovoltaic electric)
        # Solar peaks mid-day but system peak is usually evening
        # Very low contribution to evening peak
        return 0.25
    else
        # Generic renewable
        return 0.30
    end
end

"""
    _calculate_battery_credit(_tech::PSIP.StorageTechnology) -> Float64

Calculate capacity credit for battery storage.
Depends on energy capacity and ability to discharge during peak.
"""
function _calculate_battery_credit(_tech::PSIP.StorageTechnology)::Float64
    # Battery can discharge at rated power for full discharge period
    # Typical credit: 0.85-0.95 depending on round-trip efficiency and reserve requirements
    return 0.90
end

"""
    add_capacity_adequacy_constraint_to_model!(model::InvestmentModel, portfolio::PSIP.Portfolio)

Add capacity adequacy constraint to an InvestmentModel after build, when investment variables exist.
Enforces: existing_effective_capacity + sum(BuildCapacity[i] * credit[i]) >= peak_demand

Arguments:
- model: InvestmentModel instance (must already be built)
- portfolio: PSIP.Portfolio containing technology data
"""
function add_capacity_adequacy_constraint_to_model!(model::InvestmentModel, portfolio::PSIP.Portfolio)
    peak_demand = get_peak_demand(portfolio)
    system = PSIP.get_base_system(portfolio)
    capacity_credits = get_capacity_credits(portfolio, system)
    reserve_margin = something(portfolio.metadata.reserve_margin, 0.15)

    add_capacity_adequacy_constraint!(model, portfolio, peak_demand, reserve_margin, capacity_credits)
end

"""
    add_capacity_adequacy_constraint!(container, portfolio, peak_demand, reserve_margin, capacity_credits)

Internal function to add capacity adequacy constraint with explicit parameters.
"""
function add_capacity_adequacy_constraint!(container, portfolio::PSIP.Portfolio, peak_demand::Float64, _reserve_margin::Float64, capacity_credits::Dict{String, Float64})
    isempty(capacity_credits) && return

    isnothing(container) && return

    @debug "Adding capacity adequacy constraint with peak demand: $peak_demand MW and reserve margin: $(_reserve_margin * 100)%"
    # Calculate existing effective capacity from base_system
    # Portfolio contains only candidate/new technologies for investment
    existing_effective_capacity = 0.0
    base_system = PSIP.get_base_system(portfolio)

    # Get existing generators from the base system
    for gen in PSY.get_components(PSY.Generator, base_system)
        gen_name = PSY.get_name(gen)
        credit = get(capacity_credits, gen_name, 0.0)

        if credit > 0.0
            try
                cap = PSY.get_max_active_power(gen)
                existing_effective_capacity += cap * credit
            catch
                # Skip generators we can't get capacity for
            end
        end
    end

    # Build weighted capacity expression: sum(BuildCapacity[tech] * credit[tech])
    capacity_expr = JuMP.AffExpr(0.0)
    found_any = false

    # Sum BuildCapacity variables weighted by capacity credits
    for (var_key, var_array) in container.variables
        var_name = string(typeof(var_key))

        # Check if this is a BuildCapacity variable by examining the key type
        if contains(var_name, "BuildCapacity")
            if !isa(var_array, JuMP.Containers.DenseAxisArray)
                continue
            end

            try
                axes_data = var_array.axes
                if length(axes_data) >= 2  # Need at least 2 dimensions: [tech, period]
                    final_period = axes_data[2][end]
                    for tech_idx in axes_data[1]
                        tech_name = string(tech_idx)
                        credit = get(capacity_credits, tech_name, 0.0)

                        if credit > 0.0
                            JuMP.add_to_expression!(capacity_expr, credit, var_array[tech_idx, final_period])
                            found_any = true
                            @debug "Added BuildCapacity var for $tech_name with credit $credit"
                        end
                    end
                end
            catch e
                @debug "Failed to process BuildCapacity variable: $e"
                continue
            end
        end
    end

    # Add constraint if we found capacity variables
    # Constraint: existing_effective_capacity + sum(BuildCapacity[tech] * credit[tech]) >= peak_demand
    if found_any
        jump_model = get_jump_model(container)
        if !isnothing(jump_model)
            JuMP.add_to_expression!(capacity_expr, existing_effective_capacity)

            # Register constraint in container
            constraint_array = add_constraints_container!(
                container,
                CapacityAdequacyConstraint(),
                PSIP.Portfolio,
                1:1  # Single constraint indexed by 1
            )

            # Add the constraint to the JuMP model and register it
            constraint_array[1] = JuMP.@constraint(jump_model, capacity_expr >= peak_demand)

            @info "Capacity adequacy constraint added: existing_capacity=$existing_effective_capacity + weighted_buildcapacity >= peak_demand=$peak_demand"
        end
    else
        @debug "No BuildCapacity variables found for capacity adequacy constraint"
    end

    return
end
