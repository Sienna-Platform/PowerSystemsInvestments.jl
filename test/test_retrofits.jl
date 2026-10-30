const RETROFIT_THERMAL = PSIP.SupplyTechnology{PSY.ThermalStandard}
const RETROFIT_DAYS = [
    collect(DateTime(year, 1, 1, 0):Hour(1):DateTime(year, 1, 1, 23)) for
    year in (2030, 2035)
]

function _retrofit_thermal(name, zone, cost, limits; capex=0.0)
    return RETROFIT_THERMAL(;
        name=name,
        id=1,
        available=true,
        region=[zone],
        power_systems_type="ThermalStandard",
        prime_mover_type=PrimeMovers.ST,
        fuel=[ThermalFuels.COAL],
        capital_costs=PSIP.CapitalCost(LinearCurve(capex), 0.0),
        operation_costs=ThermalGenerationCost(;
            variable=CostCurve(LinearCurve(cost)),
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
end

# One zone with a 150 MW flat demand over two periods (2030, 2035), an existing coal fleet
# (coal1 100 MW, coal2 50 MW) at 60 $/MWh that is too expensive to expand (`source_capex`), gas at 100 $/MWh, and
# retrofit options at 20 $/MWh. `options` lists (name, retrofit cost $/MW, eligible units,
# retrofit efficiency); `capex_multipliers` scales the first option's cost in each period.
function _retrofit_model(;
    options=[("coal_ccs", 1e5, ["coal1", "coal2"], 1.0)],
    capex_multipliers=nothing,
    source_limits=(min=0.0, max=150.0),
    attach_to_source=true,
    option_zone=nothing,
    source_capex=1e8,
)
    sys = PSY.System(100.0)
    set_units_base_system!(sys, "NATURAL_UNITS")
    bus = ACBus(nothing)
    PSY.set_bustype!(bus, PSY.ACBusTypes.REF)
    add_component!(sys, bus)
    for (name, capacity) in (("coal1", 100.0), ("coal2", 50.0))
        unit = ThermalStandard(nothing)
        PSY.set_name!(unit, name)
        PSY.set_bus!(unit, bus)
        add_component!(sys, unit)
        PSY.set_active_power_limits!(unit, (min=0.0, max=capacity))
    end

    portfolio =
        Portfolio(sys; financial_data=PortfolioFinancialData(2025, 0.07, 0.02, 0.04))
    zone = Zone(; name="zone", id=1)
    PSIP.add_region!(portfolio, zone)
    coal = _retrofit_thermal("coal", zone, 60.0, source_limits; capex=source_capex)
    PSIP.add_technology!(portfolio, coal)
    PSIP.add_supplemental_attribute!(
        portfolio,
        coal,
        PSIP.ExistingDevices(; id=1, existing_devices=["coal1", "coal2"]),
    )
    PSIP.add_technology!(
        portfolio,
        _retrofit_thermal("gas", zone, 100.0, (min=1000.0, max=1000.0)),
    )
    for (ix, (name, cost, eligible, efficiency)) in enumerate(options)
        region = isnothing(option_zone) ? zone : option_zone
        if !(region in PSIP.get_regions(PSIP.Zone, portfolio))
            PSIP.add_region!(portfolio, region)
        end
        option = _retrofit_thermal(name, region, 20.0, (min=0.0, max=1e8); capex=cost)
        PSIP.add_technology!(portfolio, option)
        retrofit = PSIP.RetrofitPotential(;
            id=ix,
            eligible_generators=eligible,
            retrofit_efficiency=efficiency,
        )
        PSIP.add_supplemental_attribute!(portfolio, option, retrofit)
        attach_to_source && PSIP.add_supplemental_attribute!(portfolio, coal, retrofit)
        if ix == 1 && !isnothing(capex_multipliers)
            PSIP.add_time_series!(
                portfolio,
                option,
                SingleTimeSeries(
                    "inv_capex",
                    TimeArray(first.(RETROFIT_DAYS), capex_multipliers),
                ),
            )
        end
    end
    demand = PSIP.ProjectedDemand{PSY.PowerLoad}(;
        name="demand",
        id=2,
        available=true,
        region=[zone],
        power_systems_type="PowerLoad",
        conformity=PSY.LoadConformity.NON_CONFORMING,
        peak_demand_mw=150.0,
        construction_year=2030,
    )
    PSIP.add_technology!(portfolio, demand)
    for (rep_day, hours) in enumerate(RETROFIT_DAYS)
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
        OperationalRepresentativeDays(RETROFIT_DAYS, [365, 365]),
        RepresentativePeriods(Vector{Vector{DateTime}}()),
        TransportModel(SingleRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["coal", "gas"],
        RETROFIT_THERMAL,
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        first.(options),
        RETROFIT_THERMAL,
        RetrofitInvestment,
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

_retrofit_build_status(m) =
    build!(m; output_dir=mktempdir(; cleanup=true), console_level=Logging.AboveMaxLevel)

const RETROFIT_BUILT = IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT

function _solve_retrofit(m)
    @test _retrofit_build_status(m) == RETROFIT_BUILT
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    return m
end

# Retrofit capacity built by an option in each period
function _retrofits(m, name="coal_ccs")
    build = PSIN.get_variable(
        PSIN.get_optimization_container(m),
        BuildCapacity(),
        RETROFIT_THERMAL,
        "RetrofitInvestment",
    )
    return [JuMP.value(build[name, t]) for t in 1:2]
end

# Cumulative capacity of the coal fleet in each period
function _coal_capacity(m)
    capacity = PSIN.get_expression(
        PSIN.get_optimization_container(m),
        CumulativeCapacity(),
        RETROFIT_THERMAL,
        "ContinuousInvestment",
    )
    return [JuMP.value(capacity["coal", t]) for t in 1:2]
end

@testset "Retrofits convert source capacity" begin
    # A cheap retrofit converts the whole fleet in the first period
    m = _solve_retrofit(_retrofit_model())
    @test _retrofits(m) ≈ [150.0, 0.0] atol = 1e-6
    @test _coal_capacity(m) ≈ [0.0, 0.0] atol = 1e-6
    # An expensive one converts nothing
    m = _solve_retrofit(
        _retrofit_model(; options=[("coal_ccs", 1e8, ["coal1", "coal2"], 1.0)]),
    )
    @test _retrofits(m) ≈ [0.0, 0.0] atol = 1e-6
    @test _coal_capacity(m) ≈ [150.0, 150.0]
    # Only the eligible units can be converted
    m = _solve_retrofit(_retrofit_model(; options=[("coal_ccs", 1e5, ["coal1"], 1.0)]))
    @test sum(_retrofits(m)) ≈ 100.0
    @test _coal_capacity(m) ≈ [50.0, 50.0]
    # A derating retrofit gets 0.8 MW of option per MW of coal converted
    m = _solve_retrofit(
        _retrofit_model(; options=[("coal_ccs", 1e5, ["coal1", "coal2"], 0.8)]),
    )
    @test sum(_retrofits(m)) ≈ 120.0
    @test _coal_capacity(m) ≈ [0.0, 0.0] atol = 1e-6
end

@testset "Retrofits take effect from the period they are built" begin
    # The retrofit is too expensive in 2030 and cheap in 2035
    m = _solve_retrofit(_retrofit_model(; capex_multipliers=[1e3, 1.0]))
    @test _retrofits(m) ≈ [0.0, 150.0] atol = 1e-6
    @test _coal_capacity(m) ≈ [150.0, 0.0] atol = 1e-6
    # Coal runs in 2030 and not in 2035
    dispatch = PSIN.get_variable(
        PSIN.get_optimization_container(m),
        ActivePowerVariable(),
        RETROFIT_THERMAL,
        "BasicDispatch",
    )
    @test JuMP.value(dispatch["coal", 1]) ≈ 150.0
    @test JuMP.value(dispatch["coal", 25]) ≈ 0.0 atol = 1e-6
end

@testset "Several retrofit options share their source" begin
    # Two options for the same units convert 150 MW between them
    m = _solve_retrofit(
        _retrofit_model(;
            options=[
                ("coal_ccs", 1e5, ["coal1", "coal2"], 1.0),
                ("coal_h2", 2e5, ["coal1", "coal2"], 1.0),
            ],
        ),
    )
    @test sum(_retrofits(m, "coal_ccs")) + sum(_retrofits(m, "coal_h2")) ≈ 150.0
    @test _coal_capacity(m) ≈ [0.0, 0.0] atol = 1e-6
    # Each converts at most its own units
    m = _solve_retrofit(
        _retrofit_model(;
            options=[("coal_ccs", 1e5, ["coal1"], 1.0), ("coal_h2", 2e5, ["coal2"], 1.0)],
        ),
    )
    @test sum(_retrofits(m, "coal_ccs")) ≈ 100.0
    @test sum(_retrofits(m, "coal_h2")) ≈ 50.0
end

@testset "Retrofitted capacity counts toward the source's maximum" begin
    # Coal is free to build but at its maximum, so it can't replace the 30 MW lost to the
    # derating
    m = _solve_retrofit(
        _retrofit_model(;
            options=[("coal_ccs", 1e5, ["coal1", "coal2"], 0.8)],
            source_capex=0.0,
        ),
    )
    @test _coal_capacity(m) ≈ [0.0, 0.0] atol = 1e-6
    retrofitted = PSIN.get_expression(
        PSIN.get_optimization_container(m),
        RetrofitCapacity(),
        PSIP.Portfolio,
    )
    @test [JuMP.value(retrofitted["coal", t]) for t in 1:2] ≈ [150.0, 150.0]
    # With 50 MW of room under the maximum, coal replaces the 30 MW lost to the derating
    m = _solve_retrofit(
        _retrofit_model(;
            options=[("coal_ccs", 1e5, ["coal1", "coal2"], 0.8)],
            source_capex=0.0,
            source_limits=(min=0.0, max=200.0),
        ),
    )
    @test _coal_capacity(m) ≈ [30.0, 30.0]
end

@testset "Retrofit options can be in another region" begin
    m = _solve_retrofit(_retrofit_model(; option_zone=Zone(; name="other", id=2)))
    @test sum(_retrofits(m)) ≈ 150.0
    @test _coal_capacity(m) ≈ [0.0, 0.0] atol = 1e-6
end

@testset "Invalid retrofits fail at build" begin
    # Runs the linking step on a model whose build failed in it
    function link_error(m)
        @test _retrofit_build_status(m) ==
              IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.FAILED
        template = PSIN.get_template(m)
        return PSIN.link_retrofits!(
            PSIN.get_optimization_container(m),
            PSIN.get_portfolio(m),
            PSIN.names_to_technology_model_map(template.technology_models),
        )
    end
    @test_throws r"attached to it and to one source" link_error(
        _retrofit_model(; attach_to_source=false),
    )
    @test_throws r"minimum capacity" link_error(
        _retrofit_model(; source_limits=(min=10.0, max=150.0)),
    )
    @test_throws r"coal3 of coal are not among its ExistingDevices" link_error(
        _retrofit_model(; options=[("coal_ccs", 1e5, ["coal1", "coal3"], 1.0)]),
    )
    @test_throws r"retrofit_efficiency" link_error(
        _retrofit_model(; options=[("coal_ccs", 1e5, ["coal1"], 0.0)]),
    )
end
