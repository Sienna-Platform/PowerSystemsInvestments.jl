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
    weights = [365, 365]
    operations = PSIN.OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())
    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
        TransportModel(SingleRegionBalanceModel),
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

# Capital coefficients ($/MW) per investment period computed by hand, independently of the
# package: the overnight cost is paid in 30 annual payments at the WACC of the test data,
# 0.6·0.04·(1 − 0.21) + 0.4·0.10 = 0.05896, whose value at the build year is discounted at 7%
# over 30 years and then to 2025. `multipliers` are the "inv_capex" values of the periods
# starting in 2030 and 2035.
function _hand_capital_coefficients(proportional_term, multipliers)
    wacc = 0.05896
    annualized = wacc / (1 - (1 + wacc)^-30) * (1 - 1.07^-30) / 0.07
    return proportional_term * annualized .* multipliers .* [1.07^-5, 1.07^-10]
end

# 2035 capex multipliers of the test data
const CHEAP_THERMAL_CAPEX = [1.0, 6869.263 / 6937.377]
const EXPENSIVE_THERMAL_CAPEX = [1.0, 3664.307 / 3823.56]

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
        # Both techs share financial data, so the ratio of capital coefficients is the ratio
        # of the capital curve slopes times the ratio of their capex multipliers.
        @test coef_cheap ./ coef_expensive ≈
              slope_cheap / slope_expensive .* CHEAP_THERMAL_CAPEX ./
              EXPENSIVE_THERMAL_CAPEX
        @test coef_expensive ≈
              _hand_capital_coefficients(slope_expensive, EXPENSIVE_THERMAL_CAPEX)
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
        @test slope == 6937.377e3
        @test coef ≈ _hand_capital_coefficients(slope, CHEAP_THERMAL_CAPEX)
        @test coef ≈ [4.40955631e6, 3.11308409e6] rtol = 1e-8

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
        @test ic_coef ≈
              _hand_capital_coefficients(slope + interconnection, CHEAP_THERMAL_CAPEX)

        # Costs given in dollars of a later year are deflated to the base year at the 5%
        # inflation rate of the portfolio
        PSIP.set_technology_base_year!(PSIP.get_financial_data(cheap), 2030)
        inflated_container =
            _build_capital_container(p, template, capital, tech_type, tm, ["cheap_thermal"])
        inflated_coef = _capital_coefficients(
            inflated_container,
            PSIN.BuildCapacity(),
            tech_type,
            "cheap_thermal",
        )
        @test inflated_coef ≈ ic_coef * 1.05^-5
    end

    @testset "Capex time series must cover every investment period" begin
        p, op_days = test_2_zone_portfolio()
        template, capital = _capital_cost_template(op_days)
        wind_type = PSIP.SupplyTechnology{PSY.RenewableDispatch}
        tm = PSIN.TechnologyModel(
            wind_type,
            PSIN.ContinuousInvestment,
            PSIN.BasicDispatch,
            PSIN.BasicDispatchFeasibility,
        )
        wind = PSIP.get_technology(wind_type, p, "wind")
        PSIP.remove_time_series!(p, IS.SingleTimeSeries, wind, "inv_capex")
        PSIP.add_time_series!(
            p,
            wind,
            SingleTimeSeries(
                "inv_capex",
                TimeArray([DateTime("2030-01-01"), DateTime("2040-01-01")], [1.0, 0.5]),
            ),
        )
        @test_throws r"has no value for the investment period starting in 2035" _build_capital_container(
            p,
            template,
            capital,
            wind_type,
            tm,
            ["wind"],
        )
    end

    @testset "Storage charge capital cost is not supported" begin
        storage_type = PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
        p, op_days = test_2_zone_portfolio()
        template, capital = _capital_cost_template(op_days)
        tm = PSIN.TechnologyModel(
            storage_type,
            PSIN.ContinuousInvestment,
            PSIN.CyclicalStorageDispatch,
            PSIN.BasicDispatchFeasibility,
        )
        stor = PSIP.get_technology(storage_type, p, "test_storage")
        scost = PSIP.get_capital_costs_storage(stor)
        PSIP.set_capital_costs_storage!(
            stor,
            PSIP.StorageCapitalCost(;
                charge_capital_cost=LinearCurve(1000.0),
                discharge_capital_cost=PSIP.get_discharge_capital_cost(scost),
                energy_capital_cost=PSIP.get_energy_capital_cost(scost),
                interconnection_cost=0.0,
            ),
        )
        @test_throws r"has a charge capital cost" _build_capital_container(
            p,
            template,
            capital,
            storage_type,
            tm,
            ["test_storage"],
        )
    end

    @testset "Discounting must match the portfolio" begin
        p, op_days = test_2_zone_portfolio()
        periods = [
            (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
            (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
        ]
        for capital in (
            DiscountedCashFlow(0.05, Year(2025), periods),
            DiscountedCashFlow(0.07, Year(2020), periods),
        )
            template = InvestmentModelTemplate(
                capital,
                PSIN.OperationalRepresentativeDays(op_days, [365, 365]),
                RepresentativePeriods(Vector{Vector{DateTime}}()),
                TransportModel(SingleRegionBalanceModel),
            )
            container = PSIN.SingleOptimizationContainer(
                PSIN.Settings(p),
                JuMP.Model(HiGHS.Optimizer),
            )
            @test_throws r"but the portfolio has discount rate 0.07 and base year 2025" PSIN.init_optimization_container!(
                container,
                template,
                p,
            )
        end
    end
end
