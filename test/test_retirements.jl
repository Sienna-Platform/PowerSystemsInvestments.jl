const RETIREMENT_TEST_PERIODS =
    [(Date(2030, 1, 1), Date(2034, 12, 31)), (Date(2035, 1, 1), Date(2039, 12, 31))]

function _retirement_model(investment=ContinuousInvestment)
    portfolio, days = test_2_zone_portfolio()
    system = PSIP.get_base_system(portfolio)
    set_units_base_system!(system, "NATURAL_UNITS")
    bus = ACBus(nothing)
    PSY.set_bustype!(bus, PSY.ACBusTypes.REF)
    add_component!(system, bus)
    for (name, capacity) in (("unit1", 100.0), ("unit2", 50.0))
        unit = ThermalStandard(nothing)
        PSY.set_name!(unit, name)
        PSY.set_bus!(unit, bus)
        add_component!(system, unit)
        PSY.set_active_power_limits!(unit, (min=0.0, max=capacity))
    end
    thermal_type = SupplyTechnology{ThermalStandard}
    source = PSIP.get_technology(thermal_type, portfolio, "cheap_thermal")
    PSIP.add_supplemental_attribute!(
        portfolio,
        source,
        ExistingDevices(; id=100, existing_devices=["unit1", "unit2"]),
    )
    PSIP.add_supplemental_attribute!(
        portfolio,
        source,
        RetirementPotential(;
            id=101,
            eligible_generators=["unit1", "unit2"],
            planned_retirement_year=Dict("unit1" => 2032),
        ),
    )
    PSIP.set_capital_costs!(source, PSIP.CapitalCost(LinearCurve(1e9), 0.0))
    PSIP.set_unit_size!(source, 50.0)
    PSIP.set_capacity_limits!(source, (min=0.0, max=150.0))
    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), RETIREMENT_TEST_PERIODS),
        OperationalRepresentativeDays(days, [365, 365]),
        RepresentativePeriods(Vector{Vector{DateTime}}()),
        TransportModel(SingleRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["cheap_thermal", "expensive_thermal"],
        thermal_type,
        investment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["demand1"],
        ProjectedDemand{PowerLoad},
        StaticLoadInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    return InvestmentModel(
        template,
        SingleInstanceSolve,
        portfolio;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
    )
end

@testset "Scheduled retirement periods" begin
    model = _retirement_model()
    portfolio = PSIN.get_portfolio(model)
    source =
        PSIP.get_technology(SupplyTechnology{ThermalStandard}, portfolio, "cheap_thermal")
    retirement = only(PSIP.get_supplemental_attributes(RetirementPotential, source))
    days = [
        collect(DateTime(year):Hour(1):(DateTime(year) + Hour(23))) for year in (2030, 2035)
    ]
    mapping = PSIN.TimeMapping(RETIREMENT_TEST_PERIODS, days, Vector{Vector{DateTime}}())
    for (year, expected) in (
        (2025, [100.0, 0.0]),
        (2030, [100.0, 0.0]),
        (2032, [0.0, 100.0]),
        (2035, [0.0, 100.0]),
        (2040, [0.0, 0.0]),
    )
        PSIP.set_planned_retirement_year!(retirement, Dict("unit1" => year))
        @test PSIN.get_scheduled_retirements(portfolio, source, mapping) == expected
    end
    PSIP.set_planned_retirement_year!(retirement, Dict("unit1" => 2030, "unit2" => 2035))
    @test PSIN.get_scheduled_retirements(portfolio, source, mapping) == [100.0, 50.0]
    PSY.set_units_base_system!(PSIP.get_base_system(portfolio), "SYSTEM_BASE")
    @test PSIN.get_scheduled_retirements(portfolio, source, mapping) == [100.0, 50.0]
    PSIP.set_planned_retirement_year!(retirement, Dict("missing_unit" => 2035))
    @test_throws r"must be listed in both" PSIN.get_scheduled_retirements(
        portfolio,
        source,
        mapping,
    )
end

@testset "Scheduled retirements reduce installed supply" begin
    for investment in (ContinuousInvestment, IntegerInvestment)
        model = _retirement_model(investment)
        @test build!(model; output_dir=mktempdir(; cleanup=true)) ==
              IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
        @test solve!(model) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
        @test JuMP.termination_status(PSIN.get_jump_model(model)) == JuMP.MOI.OPTIMAL
        container = PSIN.get_optimization_container(model)
        thermal_type = SupplyTechnology{ThermalStandard}
        capacity = PSIN.get_expression(
            container,
            CumulativeCapacity(),
            thermal_type,
            string(investment),
        )
        @test [JuMP.value(capacity["cheap_thermal", t]) for t in 1:2] ≈ [150.0, 50.0]
        dispatch = PSIN.get_variable(
            container,
            ActivePowerVariable(),
            thermal_type,
            "BasicDispatch",
        )
        for (period, remaining) in ((1, 150.0), (2, 50.0))
            timestamps = ((period - 1) * 24 + 1):(period * 24)
            @test maximum(JuMP.value(dispatch["cheap_thermal", t]) for t in timestamps) <=
                  remaining + 1e-6
        end
    end
end
