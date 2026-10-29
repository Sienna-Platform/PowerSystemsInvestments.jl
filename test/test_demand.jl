const DEMAND_TEST_PERIODS = [
    (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
    (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
]
const DEMAND_TEST_DAYS = [
    collect(DateTime(year, 1, 1, 0):Hour(1):DateTime(year, 1, 1, 23)) for
    year in (2030, 2035)
]
const DEMAND_TYPE = PSIP.DemandRequirement{PSY.PowerLoad}
const GAS_TYPE = PSIP.SupplyTechnology{PSY.ThermalStandard}

function _demand_financial_data()
    return TechnologyFinancialData(;
        capital_recovery_period=30,
        technology_base_year=2025,
        debt_fraction=0.6,
        debt_rate=0.04,
        return_on_equity=0.10,
        tax_rate=0.21,
    )
end

# Base system with one bus and loads of (name, max active power, hourly profile in 2025)
function _demand_base_system(loads)
    sys = PSY.System(100.0)
    set_units_base_system!(sys, "NATURAL_UNITS")
    bus = ACBus(nothing)
    PSY.set_bustype!(bus, PSY.ACBusTypes.REF)
    add_component!(sys, bus)
    for (name, max_power, profile) in loads
        load = PowerLoad(nothing)
        PSY.set_name!(load, name)
        PSY.set_bus!(load, bus)
        add_component!(sys, load)
        PSY.set_max_active_power!(load, max_power)
        stamps = collect(
            DateTime(2025, 1, 1, 0):Hour(1):(DateTime(
                2025,
                1,
                1,
                0,
            ) + Hour(length(profile) - 1)),
        )
        PSY.add_time_series!(
            sys,
            load,
            SingleTimeSeries("max_active_power", TimeArray(stamps, profile)),
        )
    end
    return sys
end

function _demand(name; kwargs...)
    return DEMAND_TYPE(;
        name=name,
        id=1,
        available=true,
        power_systems_type="PowerLoad",
        kwargs...,
    )
end

# Single-zone model with a gas technology (variable cost `gas_cost`, no capital cost, up to
# `gas_max` MW) and the demands given as (demand, normalized shape or nothing, existing load
# names or nothing). Every demand uses the operations formulation `formulation`.
function _demand_test_model(
    demands;
    gas_cost=50.0,
    gas_max=1000.0,
    gas_investment=ContinuousInvestment,
    formulation=BasicDispatch,
    base_loads=[],
)
    zone = Zone(; name="Zone_1", id=1)
    portfolio = Portfolio(
        _demand_base_system(base_loads);
        financial_data=PortfolioFinancialData(2025, 0.07, 0.02, 0.04),
    )
    PSIP.add_region!(portfolio, zone)
    gas = GAS_TYPE(;
        name="gas",
        id=1,
        available=true,
        region=[zone],
        power_systems_type="ThermalStandard",
        prime_mover_type=PrimeMovers.CC,
        fuel=[ThermalFuels.NATURAL_GAS],
        capital_costs=PSIP.CapitalCost(LinearCurve(0.0), 0.0),
        operation_costs=ThermalGenerationCost(;
            variable=CostCurve(LinearCurve(gas_cost)),
            fixed=0.0,
            start_up=0.0,
            shut_down=0.0,
        ),
        capacity_limits=(min=0.0, max=gas_max),
        unit_size=10.0,
        financial_data=_demand_financial_data(),
    )
    PSIP.add_technology!(portfolio, gas)
    for (demand, shape, existing) in demands
        PSIP.set_region!(demand, [zone])
        PSIP.add_technology!(portfolio, demand)
        if !isnothing(existing)
            PSIP.add_supplemental_attribute!(
                portfolio,
                demand,
                PSIP.ExistingDevices(; existing_devices=existing),
            )
        end
        isnothing(shape) && continue
        for (rep_day, time_stamps) in enumerate(DEMAND_TEST_DAYS)
            PSIP.add_time_series!(
                portfolio,
                demand,
                SingleTimeSeries(; name="ops_demand", data=TimeArray(time_stamps, shape));
                year=string(Dates.year(first(time_stamps))),
                rep_day=rep_day,
            )
        end
    end

    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), DEMAND_TEST_PERIODS),
        OperationalRepresentativeDays(DEMAND_TEST_DAYS, [365, 365]),
        RepresentativePeriods(Vector{Vector{DateTime}}()),
        TransportModel(SingleRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["gas"],
        GAS_TYPE,
        gas_investment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        [PSIP.get_name(d) for (d, _, _) in demands],
        DEMAND_TYPE,
        StaticLoadInvestment,
        formulation,
        BasicDispatchFeasibility,
    )
    return InvestmentModel(
        template,
        SingleInstanceSolve,
        portfolio;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
        store_variable_names=true,
    )
end

_build_status(m) =
    build!(m; output_dir=mktempdir(; cleanup=true), console_level=Logging.AboveMaxLevel)

# Demand in MW of each time step, computed in a new container for the model
function _initialize_demands(m)
    p = PSIN.get_portfolio(m)
    container = PSIN.SingleOptimizationContainer(PSIN.Settings(p), JuMP.Model())
    PSIN.init_optimization_container!(container, PSIN.get_template(m), p)
    PSIN.initialize_demands!(container, p)
    return PSIN.get_expression(container, DemandExpression(), PSIP.Portfolio)
end

_demand_values(demand, name) = JuMP.constant.(demand[name, :].data)

const BUILT = IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
const BUILD_FAILED = IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.FAILED

@testset "Demand of new, existing, conforming and non-conforming loads" begin
    shape = [0.5 + 0.5 * (h == 18) for h in 0:23]
    flat = ones(24)
    m = _demand_test_model(
        [
            (
                _demand(
                    "existing_conforming";
                    conformity=PSY.LoadConformity.CONFORMING,
                    growth_rate=0.02,
                ),
                shape,
                ["load1", "load2"],
            ),
            (
                _demand(
                    "existing_non_conforming";
                    conformity=PSY.LoadConformity.NON_CONFORMING,
                    growth_rate=0.02,
                ),
                flat,
                ["load3"],
            ),
            (
                _demand(
                    "data_center";
                    conformity=PSY.LoadConformity.NON_CONFORMING,
                    peak_demand_mw=30.0,
                    construction_year=2035,
                ),
                flat,
                nothing,
            ),
            (
                _demand(
                    "new_conforming";
                    conformity=PSY.LoadConformity.CONFORMING,
                    peak_demand_mw=40.0,
                    construction_year=2030,
                    growth_rate=0.01,
                ),
                shape,
                nothing,
            ),
        ];
        # load1 and load2 peak in different hours: their coincident peak is 110 MW
        base_loads=[
            ("load1", 100.0, [1.0, 0.5, 0.2]),
            ("load2", 50.0, [0.2, 1.0, 0.4]),
            ("load3", 20.0, [1.0, 1.0, 1.0]),
        ],
    )
    @test _build_status(m) == BUILT
    demand = @test_logs (
        :warn,
        r"existing_non_conforming is non-conforming, so its growth_rate is ignored",
    ) match_mode = :any _initialize_demands(m)
    day_2030, day_2035 = 1:24, 25:48

    # Conforming demands grow from the base year (existing) or construction year (new)
    existing = _demand_values(demand, "existing_conforming")
    @test existing[day_2030] ≈ shape .* 110.0 * 1.02^5
    @test existing[day_2035] ≈ shape .* 110.0 * 1.02^10
    # Non-conforming demands do not grow
    @test _demand_values(demand, "existing_non_conforming") ≈ fill(20.0, 48)
    # New demands start in their construction year
    data_center = _demand_values(demand, "data_center")
    @test all(iszero, data_center[day_2030])
    @test data_center[day_2035] ≈ fill(30.0, 24)
    new_conforming = _demand_values(demand, "new_conforming")
    @test new_conforming[day_2030] ≈ shape .* 40.0
    @test new_conforming[day_2035] ≈ shape .* 40.0 * 1.01^5
end

@testset "Invalid demands fail at build" begin
    flat = ones(24)
    new_non_conforming(; kwargs...) =
        _demand("new"; conformity=PSY.LoadConformity.NON_CONFORMING, kwargs...)
    for (demands, message) in (
        # A new demand needs a peak
        ([(new_non_conforming(), flat, nothing)], r"positive peak_demand_mw"),
        # A new demand needs a conformity
        ([(_demand("new"; peak_demand_mw=10.0), flat, nothing)], r"undefined conformity"),
        # Every demand needs a shape
        (
            [(new_non_conforming(; peak_demand_mw=10.0), nothing, nothing)],
            r"needs a \"ops_demand\" time series",
        ),
    )
        m = _demand_test_model(demands)
        @test _build_status(m) == BUILD_FAILED
        @test_throws message _initialize_demands(m)
    end
end

# One demand of 100 MW in every hour with the given unserved demand cost
function _unserved_test_model(cost; kwargs...)
    demand = _demand(
        "demand";
        conformity=PSY.LoadConformity.NON_CONFORMING,
        peak_demand_mw=100.0,
        unserved_demand_cost=cost,
    )
    return _demand_test_model(
        [(demand, ones(24), nothing)];
        formulation=UnservedDemandDispatch,
        kwargs...,
    )
end

# Solved unserved demand of each tier in the first hour
function _solved_unserved(m)
    @test _build_status(m) == BUILT
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    unserved = PSIN.get_variable(
        PSIN.get_optimization_container(m),
        UnservedDemandVariable(),
        DEMAND_TYPE,
        "UnservedDemandDispatch",
    )
    return Dict(name => JuMP.value(unserved[name, 1]) for name in axes(unserved, 1))
end

@testset "Unserved demand with a single price" begin
    # Shedding is cheaper than gas
    @test _solved_unserved(_unserved_test_model(LinearCurve(30.0)))["demand__tier1"] ≈ 100.0
    # Gas is cheaper, but limited to 60 MW
    @test _solved_unserved(_unserved_test_model(LinearCurve(80.0); gas_max=60.0))["demand__tier1"] ≈
          40.0
    @test _solved_unserved(_unserved_test_model(LinearCurve(80.0)))["demand__tier1"] ≈ 0.0 atol =
        1e-6
end

@testset "Unserved demand tiers shed in price order" begin
    # 20% of demand at 30 USD/MWh, 30% at 70 and the rest at 1000
    cost = PiecewiseIncrementalCurve(0.0, [0.0, 0.2, 0.5, 1.0], [30.0, 70.0, 1000.0])
    unserved = _solved_unserved(_unserved_test_model(cost))
    @test unserved["demand__tier1"] ≈ 20.0
    @test unserved["demand__tier2"] ≈ 0.0 atol = 1e-6
    @test unserved["demand__tier3"] ≈ 0.0 atol = 1e-6
    # With 60 MW of gas, the next cheapest tier covers the remaining 20 MW
    unserved = _solved_unserved(_unserved_test_model(cost; gas_max=60.0))
    @test unserved["demand__tier1"] ≈ 20.0
    @test unserved["demand__tier2"] ≈ 20.0
    @test unserved["demand__tier3"] ≈ 0.0 atol = 1e-6

    @test_throws r"must start at 0" PSIN._unserved_tiers(
        PiecewiseIncrementalCurve(0.0, [0.1, 1.0], [30.0]),
    )
    @test_throws r"end at most at 1" PSIN._unserved_tiers(
        PiecewiseIncrementalCurve(0.0, [0.0, 1.5], [30.0]),
    )
    @test_throws r"not supported" PSIN._unserved_tiers(
        PiecewisePointCurve([(0.0, 0.0), (1.0, 1.0)]),
    )
end

@testset "Quadratic unserved demand cost" begin
    # The marginal cost of unserved demand, 2aU + b, equals the gas cost at U = (50 - 10) / 1
    unserved = _solved_unserved(_unserved_test_model(QuadraticCurve(0.5, 10.0, 0.0)))
    @test unserved["demand__tier1"] ≈ 40.0 rtol = 1e-4
end

@testset "Quadratic unserved demand cost with discrete variables warns" begin
    m = _unserved_test_model(
        QuadraticCurve(0.5, 10.0, 0.0);
        gas_investment=IntegerInvestment,
    )
    @test _build_status(m) == BUILT
    template = PSIN.get_template(m)
    # The model stage, which the build already ran, warns once the discrete variables exist
    @test_logs (:warn, r"mixed-integer QP") match_mode = :any PSIN.construct_technologies!(
        PSIN.get_optimization_container(m),
        PSIN.get_portfolio(m),
        ["demand"],
        PSIN.ModelConstructStage(),
        PSIN.get_operation_model(template),
        DEMAND_TYPE,
        UnservedDemandDispatch,
        PSIN.get_transport_model(template),
        PSIN.TechnologyModel[],
    )
end

# Coefficient of each unserved demand tier of the first hour in a constraint
function _unserved_coefficients(m, constraint_type, requirement_type, name)
    container = PSIN.get_optimization_container(m)
    unserved = PSIN.get_variable(
        container,
        UnservedDemandVariable(),
        DEMAND_TYPE,
        "UnservedDemandDispatch",
    )
    constraint =
        PSIN.get_constraint(container, constraint_type(), requirement_type)[name, 1]
    func = JuMP.constraint_object(constraint).func
    return Dict(
        tier => JuMP.coefficient(func, unserved[tier, 1]) for tier in axes(unserved, 1)
    )
end

# Attaches a requirement to the gas technology and the demand of a model
function _attach_requirement!(m, requirement, formulation)
    p = PSIN.get_portfolio(m)
    PSIP.add_requirement!(p, requirement)
    for (type, name) in ((GAS_TYPE, "gas"), (DEMAND_TYPE, "demand"))
        PSIP.set_requirements!(PSIP.get_technology(type, p, name), [requirement])
    end
    set_requirement_model!(
        PSIN.get_template(m),
        [PSIP.get_name(requirement)],
        typeof(requirement),
        formulation,
    )
    return
end

_reserve_margin() = PSIP.CapacityReserveMargin(;
    name="reserve_margin",
    id=1,
    available=true,
    target_year=2030,
    capacity_reserve_fraction=0.1,
)

@testset "Unserved demand in requirements" begin
    cost = PiecewiseIncrementalCurve(0.0, [0.0, 0.2, 0.5, 1.0], [30.0, 70.0, 1000.0])

    # The reserve margin credits every tier but the most expensive
    m = _unserved_test_model(cost)
    _attach_requirement!(m, _reserve_margin(), RequirementCapacityReserveMargin)
    @test _build_status(m) == BUILT
    @test _unserved_coefficients(
        m,
        CapacityReserveMarginConstraint,
        PSIP.CapacityReserveMargin,
        "reserve_margin",
    ) == Dict("demand__tier1" => 1.0, "demand__tier2" => 1.0, "demand__tier3" => 0.0)

    # A single price is involuntary shedding, so it gets no credit
    m = _unserved_test_model(LinearCurve(1000.0))
    _attach_requirement!(m, _reserve_margin(), RequirementCapacityReserveMargin)
    @test _build_status(m) == BUILT
    @test _unserved_coefficients(
        m,
        CapacityReserveMarginConstraint,
        PSIP.CapacityReserveMargin,
        "reserve_margin",
    ) == Dict("demand__tier1" => 0.0)

    # Hourly matching only covers the demand that is served
    m = _unserved_test_model(cost)
    _attach_requirement!(
        m,
        PSIP.HourlyMatching(; name="hourly_matching", id=2, available=true),
        RequirementHourlyMatching,
    )
    @test _build_status(m) == BUILT
    @test all(
        ==(1.0),
        values(
            _unserved_coefficients(
                m,
                HourlyMatchingConstraint,
                PSIP.HourlyMatching,
                "hourly_matching",
            ),
        ),
    )
end
