# Simplified solver for investment optimization
# Builds a JuMP model directly from portfolio and solves it

using JuMP

function build_model!(
    container::Any,
    template::InvestmentModelTemplate,
    portfolio::PSIP.Portfolio,
)
    # Create JuMP model with HiGHS optimizer
    model = JuMP.Model(HiGHS.Optimizer)
    set_silent(model)

    # Extract technologies and load from portfolio
    techs = PSIP.get_technologies(PSIP.Technology, portfolio)

    # Separate technologies by type
    supply_techs = [t for t in techs if t isa PSIP.SupplyTechnology]
    storage_techs = [t for t in techs if t isa PSIP.StorageTechnology]
    demand_techs = [t for t in techs if t isa PSIP.DemandRequirement]

    # Get representative periods from template
    # For now, assume we have monthly representative days (12 periods × 24 hours)
    n_periods = 12  # months
    n_hours = 24    # hours per day
    period_weights = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]  # days per month

    # =========================================================================
    # INVESTMENT DECISION VARIABLES
    # =========================================================================
    # Build capacity for each supply technology (MW)
    build_cap = Dict()
    for tech in supply_techs
        name = PSIP.get_name(tech)
        cap_limits = try
            PSIP.get_capacity_limits(tech)
        catch
            (min=0, max=1000)
        end
        if cap_limits.max > 0  # Only investable if capacity > 0
            @variable(model, 0 <= build_cap[name] <= cap_limits.max)
        else
            @variable(model, 0 <= build_cap[name] <= 0)  # Fixed to zero
        end
    end

    # Build capacity for storage (power and energy separately)
    build_storage_power = Dict()
    build_storage_energy = Dict()
    for tech in storage_techs
        name = PSIP.get_name(tech)
        try
            power_limits = PSIP.get_capacity_limits_discharge(tech)
            energy_limits = PSIP.get_capacity_limits_energy(tech)
            @variable(model, 0 <= build_storage_power[name] <= power_limits.max)
            @variable(model, 0 <= build_storage_energy[name] <= energy_limits.max)
        catch
            @variable(model, 0 <= build_storage_power[name] <= 0)
            @variable(model, 0 <= build_storage_energy[name] <= 0)
        end
    end

    # =========================================================================
    # OPERATIONAL DISPATCH VARIABLES
    # =========================================================================
    # Power output for supply technologies (MW)
    power_output = Dict()
    for tech in supply_techs
        name = PSIP.get_name(tech)
        for p in 1:n_periods, h in 1:n_hours
            @variable(model, power_output[(name, p, h)] >= 0)
        end
    end

    # Power injection/withdrawal for storage (MW, positive = discharge)
    storage_power = Dict()
    for tech in storage_techs
        name = PSIP.get_name(tech)
        for p in 1:n_periods, h in 1:n_hours
            # Signed variable: positive = discharge, negative = charge
            @variable(model, storage_power[(name, p, h)])
        end
    end

    # State of charge for storage (MWh)
    soc = Dict()
    for tech in storage_techs
        name = PSIP.get_name(tech)
        for p in 1:n_periods, h in 1:n_hours
            @variable(model, soc[(name, p, h)] >= 0)
        end
    end

    # Load curtailment (MWh, for slack if needed)
    load_shed = Dict()
    for tech in demand_techs
        name = PSIP.get_name(tech)
        for p in 1:n_periods, h in 1:n_hours
            @variable(model, 0 <= load_shed[(name, p, h)])
        end
    end

    # =========================================================================
    # CAPACITY CONSTRAINTS
    # =========================================================================
    for tech in supply_techs
        name = PSIP.get_name(tech)
        for p in 1:n_periods, h in 1:n_hours
            # Dispatch cannot exceed available capacity (existing + built)
            available_cap = try
                existing = PSIP.get_existing_capacity(tech)
                existing
            catch
                0.0
            end
            if name in keys(build_cap)
                @constraint(model, power_output[(name, p, h)] <= available_cap + build_cap[name])
            else
                @constraint(model, power_output[(name, p, h)] <= available_cap)
            end
        end
    end

    # Storage power constraints (discharge cannot exceed built capacity)
    for tech in storage_techs
        name = PSIP.get_name(tech)
        for p in 1:n_periods, h in 1:n_hours
            existing_power = try
                PSIP.get_existing_capacity_power(tech)
            catch
                0.0
            end
            @constraint(model, storage_power[(name, p, h)] <= existing_power + build_storage_power[name])
            @constraint(model, -storage_power[(name, p, h)] <= existing_power + build_storage_power[name])
        end
    end

    # Storage energy constraints (SOC cannot exceed built capacity)
    for tech in storage_techs
        name = PSIP.get_name(tech)
        for p in 1:n_periods, h in 1:n_hours
            existing_energy = try
                PSIP.get_existing_capacity_energy(tech)
            catch
                0.0
            end
            @constraint(model, soc[(name, p, h)] <= existing_energy + build_storage_energy[name])
        end
    end

    # =========================================================================
    # ENERGY BALANCE CONSTRAINTS
    # =========================================================================
    for p in 1:n_periods, h in 1:n_hours
        # Get load for this period/hour
        total_load = 0.0
        for tech in demand_techs
            name = PSIP.get_name(tech)
            try
                peak_demand = PSIP.get_peak_demand(tech)
                # Assume simple normalized demand pattern (could be refined with actual profiles)
                # For now, assume 70% of peak on average
                total_load += peak_demand * 0.7
            catch
                total_load += 25.0  # Default assumption
            end
        end

        # Energy balance: supply + storage discharge = load + storage charge + shed
        lhs = @expression(model,
            sum(power_output[(t, p, h)] for t in [PSIP.get_name(tech) for tech in supply_techs]) +
            sum(max(0, storage_power[(t, p, h)]) for t in [PSIP.get_name(tech) for tech in storage_techs]) +
            sum(load_shed[(d, p, h)] for d in [PSIP.get_name(tech) for tech in demand_techs])
        )

        charge_withdrawal = @expression(model,
            sum(-min(0, storage_power[(t, p, h)]) for t in [PSIP.get_name(tech) for tech in storage_techs])
        )

        @constraint(model, lhs == total_load + charge_withdrawal)
    end

    # =========================================================================
    # STORAGE STATE DYNAMICS
    # =========================================================================
    efficiency_in = 0.92
    efficiency_out = 0.92

    for tech in storage_techs
        name = PSIP.get_name(tech)
        for p in 1:n_periods
            for h in 1:n_hours
                h_prev = (h == 1) ? n_hours : h - 1
                p_prev = (h == 1) ? (p == 1 ? n_periods : p - 1) : p

                if h == 1 && p == 1
                    # First period: assume starting from 50% charge
                    initial_soc = try
                        energy_cap = PSIP.get_capacity_limits_energy(tech)
                        energy_cap.max * 0.5
                    catch
                        0.0
                    end
                    @constraint(model,
                        soc[(name, p, h)] == initial_soc +
                        efficiency_in * max(0, -storage_power[(name, p, h)]) -
                        (1.0 / efficiency_out) * max(0, storage_power[(name, p, h)])
                    )
                else
                    # Subsequent periods: state transition
                    @constraint(model,
                        soc[(name, p, h)] == soc[(name, p_prev, h_prev)] +
                        efficiency_in * max(0, -storage_power[(name, p, h)]) -
                        (1.0 / efficiency_out) * max(0, storage_power[(name, p, h)])
                    )
                end
            end
        end
    end

    # =========================================================================
    # OBJECTIVE FUNCTION: Minimize Total Cost
    # =========================================================================
    # Capital costs (annualized over economic life)
    capital_cost = @expression(model, 0.0)

    # Try to extract financial parameters from portfolio
    wacc = 0.07  # Default WACC
    econ_life_years = 25
    annualization_factor = (wacc * (1 + wacc)^econ_life_years) / ((1 + wacc)^econ_life_years - 1)

    try
        portfolio_base_year = PSIP.get_base_year(portfolio)
        portfolio_wacc = PSIP.get_wacc(portfolio)
        wacc = portfolio_wacc
    catch
        # Use defaults
    end

    # Supply technology investment costs
    for tech in supply_techs
        name = PSIP.get_name(tech)
        if name in keys(build_cap)
            try
                capital_curve = PSIP.get_capital_costs(tech)
                # Assume LinearCurve.value is cost per MW
                cost_per_mw = capital_curve.value
                capital_cost += annualization_factor * cost_per_mw * build_cap[name]
            catch
                # If can't extract cost, use zero
            end
        end
    end

    # Storage investment costs
    for tech in storage_techs
        name = PSIP.get_name(tech)
        if name in keys(build_storage_power)
            try
                power_cost_curve = PSIP.get_capital_costs_discharge(tech)
                energy_cost_curve = PSIP.get_capital_costs_energy(tech)
                power_cost_per_mw = power_cost_curve.value
                energy_cost_per_mwh = energy_cost_curve.value
                capital_cost += annualization_factor * power_cost_per_mw * build_storage_power[name]
                capital_cost += annualization_factor * energy_cost_per_mwh * build_storage_energy[name]
            catch
                # If can't extract cost, use zero
            end
        end
    end

    # Operational costs (variable + fixed)
    operational_cost = @expression(model, 0.0)

    # Variable costs for supply technologies
    for tech in supply_techs
        name = PSIP.get_name(tech)
        try
            var_cost_curve = PSIP.get_variable_cost(tech)
            cost_per_mwh = var_cost_curve.value
            for p in 1:n_periods
                for h in 1:n_hours
                    operational_cost += cost_per_mwh * power_output[(name, p, h)] * (period_weights[p] / 30.0)
                end
            end
        catch
            # No variable cost
        end
    end

    # Load shedding penalty (very high to avoid in optimal solution)
    voll = 5000.0  # Value of lost load in $/MWh
    shed_penalty = @expression(model, voll * sum(load_shed))

    # Total objective
    @objective(model, Min, capital_cost + operational_cost + shed_penalty)

    # Store model in container
    if hasfield(typeof(container), :jump_model)
        container.jump_model = model
    end

    return model
end

function solve_model!(container::Any, portfolio::PSIP.Portfolio)
    # Get JuMP model from container
    model = if hasfield(typeof(container), :jump_model)
        container.jump_model
    else
        return ISOPT.RunStatus.FAILED
    end

    # Solve the model
    try
        JuMP.optimize!(model)
        status = termination_status(model)

        if status == OPTIMAL
            return ISOPT.RunStatus.SUCCESSFULLY_FINALIZED
        else
            @warn "Optimization did not converge: $status"
            return ISOPT.RunStatus.FAILED
        end
    catch e
        @error "Solver failed: $e"
        return ISOPT.RunStatus.FAILED
    end
end

function get_investment_results(model::JuMP.Model, portfolio::PSIP.Portfolio)
    """
    Extract investment decisions from solved model.
    Returns: Dict with technology names and built capacity in MW.
    """
    results = Dict()

    # Get all variables from model
    for (var_name, var) in object_dictionary(model)
        if occursin("build_cap", String(var_name))
            tech_name = replace(String(var_name), "build_cap[" => "", "]" => "")
            results[tech_name] = value(var)
        elseif occursin("build_storage", String(var_name))
            tech_name = replace(String(var_name), "build_storage_power[" => "", "build_storage_energy[" => "", "]" => "")
            results[tech_name] = value(var)
        end
    end

    return results
end

function serialize_metadata!(container::Any, output_dir::String)
    # Placeholder for metadata serialization
    return
end
