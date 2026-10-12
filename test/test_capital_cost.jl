# Unit tests for capital cost calculation in the investment objective, exercising
# the CapitalCost / StorageCapitalCost structs with and without interconnection costs.
#
# The capital cost pipeline adds, to the objective's capital terms, the term
#   npv_proportional_term(t) * BuildVar[name, t]
# for each investment step t, where npv_proportional_term(t) is the amortized,
# net-present-value capital cost per MW. We recover npv_proportional_term(t) with
# JuMP.coefficient and assert on it directly, which is independent of the (constant)
# amortization/discount factors shared across otherwise-identical technologies.

function _capital_cost_template(op_days)
    capital = DiscountedCashFlow(
        0.07, # discount rate
        Year(2025), # base year
        [
            (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
            (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
        ],
    )
    weights = [365 * 5, 365 * 5]
    operations = PSIN.OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())
    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
        TransportModel(SingleRegionBalanceModel, use_slacks=false),
    )
    return template, capital
end

# Build a container and run only the capital-cost argument + model construction stages
# for a single technology type, so the `CapitalCost` investment expression is populated.
function _build_capital_container(p, template, capital, tech_type, tech_model, names)
    settings = PSIN.Settings(p)
    model = JuMP.Model(HiGHS.Optimizer)
    container = PSIN.SingleOptimizationContainer(settings, model)
    PSIN.init_optimization_container!(container, template, p)
    transport_model = PSIN.get_transport_model(template)
    PSIN.initialize_system_expressions!(container, transport_model, p)

    models = [tech_model for _ in names]
    PSIN.construct_technologies!(
        container,
        p,
        names,
        PSIN.ArgumentConstructStage(),
        capital,
        tech_type,
        PSIN.ContinuousInvestment,
        transport_model,
        models,
    )
    PSIN.construct_technologies!(
        container,
        p,
        names,
        PSIN.ModelConstructStage(),
        capital,
        tech_type,
        PSIN.ContinuousInvestment,
        transport_model,
        models,
    )
    return container
end

# Per-investment-step capital cost coefficient on `build_var` for technology `name`.
function _capital_coefficients(container, build_var, tech_type, name)
    capital_terms = PSIN.get_capital_terms(container.objective_function)
    vars = PSIN.get_variable(container, build_var, tech_type, "ContinuousInvestment")
    inv_steps = PSIN.get_investment_time_steps(container.time_mapping)
    return [JuMP.coefficient(capital_terms, vars[name, t]) for t in inv_steps]
end

_curve_slope(vc) = PSY.get_proportional_term(PSY.get_function_data(vc))

# Closed-form expected capital coefficient per investment step, mirroring
# amortize_overnight_term_to_base_year_dollars + the NPV discounting in
# _add_linearcurve_cost!. `proportional_term` is the capital ($/MW) slope plus any
# interconnection cost ($/MW). The objective multiplier for BuildCapacity is 1.0.
function _expected_capital_coefficients(container, tech, proportional_term)
    fin = PSIP.get_financial_data(tech)
    base_year = PSIN.get_base_year(container)
    discount_rate = PSIN.get_discount_rate(container)
    inflation_rate = PSIN.get_inflation_rate(container)
    wacc = PSIP.get_wacc(fin)
    crp = PSIP.get_capital_recovery_period(fin)
    tech_base_year = PSIP.get_technology_base_year(fin)

    capital_recovery_factor = wacc / (1 - (1 + wacc)^(-(crp)))
    lump_amortized_payments = (1 - (1 + discount_rate)^(-(crp))) / discount_rate
    dollars_to_base_year = (1.0 + inflation_rate)^(-(tech_base_year - base_year))
    amortized_proportional_term =
        proportional_term *
        capital_recovery_factor *
        lump_amortized_payments *
        dollars_to_base_year
    discount_factor = 1 / (1 + discount_rate)

    inv_tuples = PSIN.get_investment_time_stamps(container.time_mapping)
    inv_steps = PSIN.get_investment_time_steps(container.time_mapping)
    return [
        begin
            year = Dates.value.(Dates.Year.(inv_tuples[t][1]))
            amortized_proportional_term * discount_factor^(year - base_year)
        end for t in inv_steps
    ]
end

@testset "Capital Cost Calculation" begin
    tech_type = PSIP.SupplyTechnology{PSY.ThermalStandard}

    @testset "Supply capital scales with the capital curve (no interconnection)" begin
        p, op_days = test_2_zone_portfolio()
        template, capital = _capital_cost_template(op_days)
        container = _build_capital_container(
            p,
            template,
            capital,
            tech_type,
            PSIN.TechnologyModel(
                tech_type,
                PSIN.ContinuousInvestment,
                PSIN.BasicDispatch,
                PSIN.BasicDispatchFeasibility,
            ),
            ["cheap_thermal", "expensive_thermal"],
        )

        cheap = PSIP.get_technology(tech_type, p, "cheap_thermal")
        expensive = PSIP.get_technology(tech_type, p, "expensive_thermal")
        slope_cheap = _curve_slope(PSIP.get_capital_cost(PSIP.get_capital_costs(cheap)))
        slope_expensive =
            _curve_slope(PSIP.get_capital_cost(PSIP.get_capital_costs(expensive)))

        coef_cheap = _capital_coefficients(
            container,
            PSIN.BuildCapacity(),
            tech_type,
            "cheap_thermal",
        )
        coef_expensive = _capital_coefficients(
            container,
            PSIN.BuildCapacity(),
            tech_type,
            "expensive_thermal",
        )

        @test all(>(0), coef_cheap)
        @test all(>(0), coef_expensive)
        # Both interconnection costs are zero, and both techs share financial data, so the
        # amortization/discount factors are identical: the ratio of capital coefficients
        # must equal the ratio of the capital curve slopes.
        for (cc, ce) in zip(coef_cheap, coef_expensive)
            @test cc / ce ≈ slope_cheap / slope_expensive
        end
    end

    @testset "Supply interconnection cost adds to the per-MW capital term" begin
        p, op_days = test_2_zone_portfolio()
        template, capital = _capital_cost_template(op_days)
        tm = PSIN.TechnologyModel(
            tech_type,
            PSIN.ContinuousInvestment,
            PSIN.BasicDispatch,
            PSIN.BasicDispatchFeasibility,
        )

        # Baseline: interconnection_cost == 0.0
        base_coef = _capital_coefficients(
            _build_capital_container(
                p,
                template,
                capital,
                tech_type,
                tm,
                ["cheap_thermal"],
            ),
            PSIN.BuildCapacity(),
            tech_type,
            "cheap_thermal",
        )

        # Same capital curve, but now with a nonzero interconnection cost ($/MW).
        cheap = PSIP.get_technology(tech_type, p, "cheap_thermal")
        curve = PSIP.get_capital_cost(PSIP.get_capital_costs(cheap))
        slope = _curve_slope(curve)
        interconnection = 0.25 * slope
        PSIP.set_capital_costs!(cheap, PSIP.CapitalCost(curve, interconnection))

        ic_coef = _capital_coefficients(
            _build_capital_container(
                p,
                template,
                capital,
                tech_type,
                tm,
                ["cheap_thermal"],
            ),
            PSIN.BuildCapacity(),
            tech_type,
            "cheap_thermal",
        )

        for (b, w) in zip(base_coef, ic_coef)
            @test w > b
            # Interconnection ($/MW) is added directly to the capital slope ($/MW).
            @test w ≈ b * (slope + interconnection) / slope
        end
    end

    @testset "Storage interconnection applies to power capacity, not energy" begin
        storage_type = PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
        p, op_days = test_2_zone_portfolio()
        template, capital = _capital_cost_template(op_days)
        tm = PSIN.TechnologyModel(
            storage_type,
            PSIN.ContinuousInvestment,
            PSIN.CyclicalStorageDispatch,
            PSIN.BasicDispatchFeasibility,
        )

        base_container = _build_capital_container(
            p,
            template,
            capital,
            storage_type,
            tm,
            ["test_storage"],
        )
        base_power = _capital_coefficients(
            base_container,
            PSIN.BuildPowerCapacity(),
            storage_type,
            "test_storage",
        )
        base_energy = _capital_coefficients(
            base_container,
            PSIN.BuildEnergyCapacity(),
            storage_type,
            "test_storage",
        )

        stor = PSIP.get_technology(storage_type, p, "test_storage")
        scost = PSIP.get_capital_costs_storage(stor)
        discharge_slope = _curve_slope(PSIP.get_discharge_capital_cost(scost))
        interconnection = 0.5 * discharge_slope
        PSIP.set_capital_costs_storage!(
            stor,
            PSIP.StorageCapitalCost(
                charge_capital_cost=PSIP.get_charge_capital_cost(scost),
                discharge_capital_cost=PSIP.get_discharge_capital_cost(scost),
                energy_capital_cost=PSIP.get_energy_capital_cost(scost),
                interconnection_cost=interconnection,
            ),
        )

        ic_container = _build_capital_container(
            p,
            template,
            capital,
            storage_type,
            tm,
            ["test_storage"],
        )
        ic_power = _capital_coefficients(
            ic_container,
            PSIN.BuildPowerCapacity(),
            storage_type,
            "test_storage",
        )
        ic_energy = _capital_coefficients(
            ic_container,
            PSIN.BuildEnergyCapacity(),
            storage_type,
            "test_storage",
        )

        # Power (discharge) capital picks up the interconnection cost ($/MW) ...
        for (b, w) in zip(base_power, ic_power)
            @test w > b
            @test w ≈ b * (discharge_slope + interconnection) / discharge_slope
        end
        # ... while energy capital ($/MWh) is unchanged.
        for (b, w) in zip(base_energy, ic_energy)
            @test w ≈ b
        end
    end

    @testset "Amortized NPV capital cost matches closed form" begin
        p, op_days = test_2_zone_portfolio()
        template, capital = _capital_cost_template(op_days)
        tm = PSIN.TechnologyModel(
            tech_type,
            PSIN.ContinuousInvestment,
            PSIN.BasicDispatch,
            PSIN.BasicDispatchFeasibility,
        )

        cheap = PSIP.get_technology(tech_type, p, "cheap_thermal")
        slope = _curve_slope(PSIP.get_capital_cost(PSIP.get_capital_costs(cheap)))

        # Without interconnection: amortized/discounted term is driven by the curve slope.
        container =
            _build_capital_container(p, template, capital, tech_type, tm, ["cheap_thermal"])
        coef = _capital_coefficients(
            container,
            PSIN.BuildCapacity(),
            tech_type,
            "cheap_thermal",
        )
        expected = _expected_capital_coefficients(container, cheap, slope)
        @test length(coef) == length(expected)
        for (c, e) in zip(coef, expected)
            @test c ≈ e
        end

        # With interconnection: the amortized/discounted term uses slope + interconnection.
        interconnection = 1234.5
        PSIP.set_capital_costs!(
            cheap,
            PSIP.CapitalCost(
                PSIP.get_capital_cost(PSIP.get_capital_costs(cheap)),
                interconnection,
            ),
        )
        ic_container =
            _build_capital_container(p, template, capital, tech_type, tm, ["cheap_thermal"])
        ic_coef = _capital_coefficients(
            ic_container,
            PSIN.BuildCapacity(),
            tech_type,
            "cheap_thermal",
        )
        ic_expected =
            _expected_capital_coefficients(ic_container, cheap, slope + interconnection)
        for (c, e) in zip(ic_coef, ic_expected)
            @test c ≈ e
        end
    end
end
