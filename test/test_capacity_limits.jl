# Capacity limits: the minimum and maximum apply to cumulative capacity (existing plus built)
# in every investment period, not to the capacity built in a period.

const LIMIT_THERMAL = PSIP.SupplyTechnology{PSY.ThermalStandard}

# Runs the capital stages of one technology type of the two-zone test portfolio
function _limit_container(p, op_days, tech_type, names)
    capital = DiscountedCashFlow(
        0.07,
        Year(2025),
        [
            (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
            (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
        ],
    )
    template = InvestmentModelTemplate(
        capital,
        PSIN.OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(SingleRegionBalanceModel),
    )
    container = PSIN.SingleOptimizationContainer(PSIN.Settings(p), JuMP.Model())
    PSIN.init_optimization_container!(container, template, p)
    transport_model = PSIN.get_transport_model(template)
    PSIN.initialize_system_expressions!(container, transport_model, p)
    models = [
        TechnologyModel(
            tech_type,
            ContinuousInvestment,
            BasicDispatch,
            BasicDispatchFeasibility,
        ) for _ in names
    ]
    for stage in (PSIN.ArgumentConstructStage(), PSIN.ModelConstructStage())
        PSIN.construct_technologies!(
            container,
            p,
            names,
            stage,
            capital,
            tech_type,
            ContinuousInvestment,
            transport_model,
            models,
        )
    end
    return container
end

# (lower, upper) of the cumulative limit of a technology in each investment period
function _cumulative_limits(container, constraint_type, tech_type, name)
    constraints =
        PSIN.get_constraint(container, constraint_type(), tech_type, "ContinuousInvestment")
    return [
        (
            JuMP.constraint_object(constraints[name, t]).set.lower,
            JuMP.constraint_object(constraints[name, t]).set.upper,
        ) for t in axes(constraints, 2)
    ]
end

@testset "Capacity limits apply to cumulative capacity" begin
    # Supply: the build variable is only non-negative
    p, op_days = test_2_zone_portfolio()
    thermal = PSIP.get_technology(LIMIT_THERMAL, p, "cheap_thermal")
    PSIP.set_capacity_limits!(thermal, (min=50.0, max=400.0))
    container = _limit_container(p, op_days, LIMIT_THERMAL, ["cheap_thermal"])
    @test _cumulative_limits(
        container,
        PSIN.CumulativeCapacityLimit,
        LIMIT_THERMAL,
        "cheap_thermal",
    ) == [(50.0, 400.0), (50.0, 400.0)]
    build =
        PSIN.get_variable(container, BuildCapacity(), LIMIT_THERMAL, "ContinuousInvestment")
    @test all(JuMP.lower_bound(build["cheap_thermal", t]) == 0.0 for t in 1:2)
    @test !any(JuMP.has_upper_bound(build["cheap_thermal", t]) for t in 1:2)

    # Storage: power from the discharge limits, and energy
    p, op_days = test_2_zone_portfolio()
    storage_type = PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
    storage = PSIP.get_technology(storage_type, p, "test_storage")
    PSIP.set_capacity_limits_discharge!(storage, (min=20.0, max=300.0))
    PSIP.set_capacity_limits_energy!(storage, (min=80.0, max=1000.0))
    container = _limit_container(p, op_days, storage_type, ["test_storage"])
    @test _cumulative_limits(
        container,
        PSIN.CumulativePowerCapacityLimit,
        storage_type,
        "test_storage",
    ) == [(20.0, 300.0), (20.0, 300.0)]
    @test _cumulative_limits(
        container,
        PSIN.CumulativeEnergyCapacityLimit,
        storage_type,
        "test_storage",
    ) == [(80.0, 1000.0), (80.0, 1000.0)]

    # Co-located: storage power and energy, wind, solar and inverter
    p, op_days = test_2_zone_portfolio()
    colocated_type = PSIP.ColocatedSupplyStorageTechnology{PSY.RenewableDispatch}
    colocated = PSIP.get_technology(colocated_type, p, "colocated_test")
    PSIP.set_capacity_power_limits!(colocated, (min=1.0, max=100.0))
    PSIP.set_capacity_energy_limits!(colocated, (min=2.0, max=200.0))
    PSIP.set_capacity_limits_wind!(colocated, (min=3.0, max=300.0))
    PSIP.set_capacity_limits_solar!(colocated, (min=4.0, max=400.0))
    PSIP.set_min_inverter_capacity!(colocated, 5.0)
    PSIP.set_max_inverter_capacity!(colocated, 500.0)
    container = _limit_container(p, op_days, colocated_type, ["colocated_test"])
    for (constraint_type, limits) in (
        (PSIN.CumulativePowerCapacityLimit, (1.0, 100.0)),
        (PSIN.CumulativeEnergyCapacityLimit, (2.0, 200.0)),
        (PSIN.CumulativeWindCapacityLimit, (3.0, 300.0)),
        (PSIN.CumulativeSolarCapacityLimit, (4.0, 400.0)),
        (PSIN.CumulativeInverterCapacityLimit, (5.0, 500.0)),
    )
        @test _cumulative_limits(
            container,
            constraint_type,
            colocated_type,
            "colocated_test",
        ) == [limits, limits]
    end

    # Transmission
    p, op_days = test_2_zone_portfolio()
    line_type = PSIP.AggregateTransportTechnology{PSY.ACBranch}
    line = PSIP.get_technology(line_type, p, "test_branch")
    PSIP.set_capacity_limits!(line, (min=100.0, max=1000.0))
    container = _limit_container(p, op_days, line_type, ["test_branch"])
    @test _cumulative_limits(
        container,
        PSIN.CumulativeCapacityLimit,
        line_type,
        "test_branch",
    ) == [(100.0, 1000.0), (100.0, 1000.0)]

    # A minimum above the maximum is an error
    p, op_days = test_2_zone_portfolio()
    thermal = PSIP.get_technology(LIMIT_THERMAL, p, "cheap_thermal")
    PSIP.set_capacity_limits!(thermal, (min=500.0, max=400.0))
    @test_throws r"above its maximum" _limit_container(
        p,
        op_days,
        LIMIT_THERMAL,
        ["cheap_thermal"],
    )
end

const LIMIT_DAYS = [
    collect(DateTime(year, 1, 1, 0):Hour(1):DateTime(year, 1, 1, 23)) for
    year in (2030, 2035)
]

# One zone with a 100 MW flat demand and one gas technology with the given capacity limits,
# over two investment periods. With `existing`, the gas technology has a 200 MW generator in the
# base system.
function _limit_model(limits; existing=false)
    sys = PSY.System(100.0)
    set_units_base_system!(sys, "NATURAL_UNITS")
    bus = ACBus(nothing)
    PSY.set_bustype!(bus, PSY.ACBusTypes.REF)
    add_component!(sys, bus)
    generator = ThermalStandard(nothing)
    PSY.set_name!(generator, "existing_gas")
    PSY.set_bus!(generator, bus)
    add_component!(sys, generator)
    PSY.set_active_power_limits!(generator, (min=0.0, max=200.0))

    portfolio =
        Portfolio(sys; financial_data=PortfolioFinancialData(2025, 0.07, 0.02, 0.04))
    zone = Zone(; name="zone", id=1)
    PSIP.add_region!(portfolio, zone)
    gas = LIMIT_THERMAL(;
        name="gas",
        id=1,
        available=true,
        region=[zone],
        power_systems_type="ThermalStandard",
        prime_mover_type=PrimeMovers.CC,
        fuel=[ThermalFuels.NATURAL_GAS],
        capital_costs=PSIP.CapitalCost(LinearCurve(1e5), 0.0),
        operation_costs=ThermalGenerationCost(;
            variable=CostCurve(LinearCurve(30.0)),
            fixed=0.0,
            start_up=0.0,
            shut_down=0.0,
        ),
        capacity_limits=limits,
        outage_factors=(planned=0.0, forced=0.0),
        financial_data=TechnologyFinancialData(;
            capital_recovery_period=30,
            technology_base_year=2025,
            debt_fraction=0.6,
            debt_rate=0.04,
            return_on_equity=0.10,
            tax_rate=0.21,
        ),
    )
    PSIP.add_technology!(portfolio, gas)
    if existing
        PSIP.add_supplemental_attribute!(
            portfolio,
            gas,
            PSIP.ExistingDevices(; id=1, existing_devices=["existing_gas"]),
        )
    end
    demand = PSIP.ProjectedDemand{PSY.PowerLoad}(;
        name="demand",
        id=2,
        available=true,
        region=[zone],
        power_systems_type="PowerLoad",
        conformity=PSY.LoadConformity.NON_CONFORMING,
        peak_demand_mw=100.0,
        construction_year=2030,
    )
    PSIP.add_technology!(portfolio, demand)
    for (rep_day, hours) in enumerate(LIMIT_DAYS)
        PSIP.add_time_series!(
            portfolio,
            demand,
            SingleTimeSeries(; name="ops_demand", data=TimeArray(hours, ones(24)));
            year=string(Dates.year(first(hours))),
            rep_day=rep_day,
        )
    end

    template = InvestmentModelTemplate(
        DiscountedCashFlow(
            0.07,
            Year(2025),
            [
                (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
                (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
            ],
        ),
        OperationalRepresentativeDays(LIMIT_DAYS, [365, 365]),
        RepresentativePeriods(Vector{Vector{DateTime}}()),
        TransportModel(SingleRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["gas"],
        LIMIT_THERMAL,
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["demand"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
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

# Capacity built in each period
function _solved_builds(m)
    @test build!(
        m;
        output_dir=mktempdir(; cleanup=true),
        console_level=Logging.AboveMaxLevel,
    ) == IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    build = PSIN.get_variable(
        PSIN.get_optimization_container(m),
        BuildCapacity(),
        LIMIT_THERMAL,
        "ContinuousInvestment",
    )
    return [JuMP.value(build["gas", t]) for t in 1:2]
end

@testset "Capacity limits over several investment periods" begin
    # A fixed capacity (min = max) is built once, not in every period
    @test _solved_builds(_limit_model((min=150.0, max=150.0))) ≈ [150.0, 0.0] atol = 1e-6
    # A minimum above the demand forces exactly that capacity
    @test _solved_builds(_limit_model((min=120.0, max=1e8))) ≈ [120.0, 0.0] atol = 1e-6
    # Existing capacity above the minimum needs nothing built
    @test _solved_builds(_limit_model((min=150.0, max=1e8); existing=true)) ≈ [0.0, 0.0] atol =
        1e-6
    # A minimum above the existing capacity forces only the shortfall
    @test _solved_builds(_limit_model((min=250.0, max=1e8); existing=true)) ≈ [50.0, 0.0] atol =
        1e-6
end
