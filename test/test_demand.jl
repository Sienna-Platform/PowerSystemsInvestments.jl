const DEMAND_TEST_PERIODS = [
    (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
    (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
]
const DEMAND_TEST_DAYS = [
    collect(DateTime(year, 1, 1, 0):Hour(1):DateTime(year, 1, 1, 23)) for
    year in (2030, 2035)
]
const DEMAND_TYPE = PSIP.ProjectedDemand{PSY.PowerLoad}
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

# One demand of 100 MW in every hour, with the given value of lost load and curtailment
function _unserved_test_model(;
    value_of_lost_load,
    max_demand_curtailment=0.0,
    curtailment_cost=LinearCurve(0.0),
    kwargs...,
)
    demand = _demand(
        "demand";
        conformity=PSY.LoadConformity.NON_CONFORMING,
        peak_demand_mw=100.0,
        value_of_lost_load=value_of_lost_load,
        max_demand_curtailment=max_demand_curtailment,
        curtailment_cost=curtailment_cost,
    )
    return _demand_test_model(
        [(demand, ones(24), nothing)];
        formulation=UnservedDemandDispatch,
        kwargs...,
    )
end

# 20% of demand curtailable at 30 USD/MWh, 30% at 70 and the rest shed at 1000
_tiered_test_model(; kwargs...) = _unserved_test_model(;
    value_of_lost_load=1000.0,
    max_demand_curtailment=0.5,
    curtailment_cost=PiecewiseIncrementalCurve(0.0, [0.0, 0.2, 0.5], [30.0, 70.0]),
    kwargs...,
)

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

@testset "Unserved demand at the value of lost load" begin
    # Shedding is cheaper than gas
    @test _solved_unserved(_unserved_test_model(; value_of_lost_load=30.0))["demand__tier1"] ≈
          100.0
    # Gas is cheaper, but limited to 60 MW
    unserved =
        _solved_unserved(_unserved_test_model(; value_of_lost_load=80.0, gas_max=60.0))
    @test unserved["demand__tier1"] ≈ 40.0
    unserved = _solved_unserved(_unserved_test_model(; value_of_lost_load=80.0))
    @test unserved["demand__tier1"] ≈ 0.0 atol = 1e-6
end

@testset "Curtailment tiers shed in price order" begin
    unserved = _solved_unserved(_tiered_test_model())
    @test unserved["demand__tier1"] ≈ 20.0
    @test unserved["demand__tier2"] ≈ 0.0 atol = 1e-6
    @test unserved["demand__tier3"] ≈ 0.0 atol = 1e-6
    # With 60 MW of gas, the next cheapest tier covers the remaining 20 MW
    unserved = _solved_unserved(_tiered_test_model(; gas_max=60.0))
    @test unserved["demand__tier1"] ≈ 20.0
    @test unserved["demand__tier2"] ≈ 20.0
    @test unserved["demand__tier3"] ≈ 0.0 atol = 1e-6
    # A single curtailment price covers all curtailable demand, and shedding only the rest
    unserved = _solved_unserved(
        _unserved_test_model(;
            value_of_lost_load=1000.0,
            max_demand_curtailment=0.3,
            curtailment_cost=LinearCurve(30.0),
            gas_max=50.0,
        ),
    )
    @test unserved["demand__tier1"] ≈ 30.0
    @test unserved["demand__tier2"] ≈ 20.0

    tiers(; kwargs...) = PSIN._unserved_tiers(_demand("demand"; kwargs...))
    @test tiers(; value_of_lost_load=500.0) == [(1.0, 500.0)]
    @test_throws r"must start at 0" tiers(;
        max_demand_curtailment=0.5,
        curtailment_cost=PiecewiseIncrementalCurve(0.0, [0.1, 0.5], [30.0]),
    )
    @test_throws r"end at max_demand_curtailment" tiers(;
        max_demand_curtailment=0.5,
        curtailment_cost=PiecewiseIncrementalCurve(0.0, [0.0, 0.4], [30.0]),
    )
    @test_throws r"between 0 and 1" tiers(; max_demand_curtailment=1.5)
    @test_throws r"not supported" tiers(;
        max_demand_curtailment=0.5,
        curtailment_cost=PiecewisePointCurve([(0.0, 0.0), (0.5, 1.0)]),
    )
end

@testset "Curtailment fields that are set inconsistently warn" begin
    # Adds the unserved demand variables of the model's demand in a new container
    function add_unserved_variables(m)
        p = PSIN.get_portfolio(m)
        container = PSIN.SingleOptimizationContainer(PSIN.Settings(p), JuMP.Model())
        PSIN.init_optimization_container!(container, PSIN.get_template(m), p)
        PSIN.initialize_demands!(container, p)
        demand = PSIP.get_technology(DEMAND_TYPE, p, "demand")
        return () -> PSIN.add_variable!(
            container,
            UnservedDemandVariable(),
            [demand],
            UnservedDemandDispatch(),
        )
    end

    free = add_unserved_variables(
        _unserved_test_model(; value_of_lost_load=1000.0, max_demand_curtailment=0.2),
    )
    @test_logs (:warn, r"at no cost") free()
    unused = add_unserved_variables(
        _unserved_test_model(;
            value_of_lost_load=1000.0,
            curtailment_cost=LinearCurve(30.0),
        ),
    )
    @test_logs (:warn, r"never curtailed") unused()
    consistent = add_unserved_variables(_tiered_test_model())
    @test_logs min_level = Logging.Warn consistent()
    @test_throws r"Is max_demand_curtailment unset" PSIN._unserved_tiers(
        _demand(
            "demand";
            curtailment_cost=PiecewiseIncrementalCurve(0.0, [0.0, 0.2], [30.0]),
        ),
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
    # The reserve margin credits curtailment, not involuntary shedding
    m = _tiered_test_model()
    _attach_requirement!(m, _reserve_margin(), RequirementCapacityReserveMargin)
    @test _build_status(m) == BUILT
    @test _unserved_coefficients(
        m,
        CapacityReserveMarginConstraint,
        PSIP.CapacityReserveMargin,
        "reserve_margin",
    ) == Dict("demand__tier1" => 1.0, "demand__tier2" => 1.0, "demand__tier3" => 0.0)

    # Without curtailment there is nothing to credit
    m = _unserved_test_model(; value_of_lost_load=1000.0)
    _attach_requirement!(m, _reserve_margin(), RequirementCapacityReserveMargin)
    @test _build_status(m) == BUILT
    @test _unserved_coefficients(
        m,
        CapacityReserveMarginConstraint,
        PSIP.CapacityReserveMargin,
        "reserve_margin",
    ) == Dict("demand__tier1" => 0.0)

    # Hourly matching only covers the demand that is served
    m = _tiered_test_model()
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

# A 100 MW flexible demand at 50% except in hour 18 (100%) and, by default, hour 19 (80%),
# with up to 80 MW of gas, so hour 18 has 20 MW more demand than gas. A small shift cost
# keeps the model from shifting where it gains nothing.
function _flexible_test_model(;
    gas_max=80.0,
    hour_19=0.8,
    shift_cost=LinearCurve(0.01),
    kwargs...,
)
    shape = [h == 18 ? 1.0 : h == 19 ? hour_19 : 0.5 for h in 0:23]
    demand = _demand(
        "demand";
        conformity=PSY.LoadConformity.NON_CONFORMING,
        peak_demand_mw=100.0,
        value_of_lost_load=10_000.0,
        flexible_fraction=0.2,
        shift_cost=shift_cost,
        kwargs...,
    )
    return _demand_test_model(
        [(demand, shape, nothing)];
        formulation=FlexibleDemandDispatch,
        gas_max=gas_max,
    )
end

# Solved values of a flexible demand variable in the hours of the first representative day
function _flexible_values(m, variable_type, name="demand")
    variable = PSIN.get_variable(
        PSIN.get_optimization_container(m),
        variable_type(),
        DEMAND_TYPE,
        "FlexibleDemandDispatch",
    )
    return [JuMP.value(variable[name, h + 1]) for h in 0:23]
end

function _solved_flexible(m)
    @test _build_status(m) == BUILT
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    return m
end

@testset "Flexible demand without a window is its baseline" begin
    m = _solved_flexible(_flexible_test_model())
    # 20 MW of hour 18 is shed, as under UnservedDemandDispatch
    @test _flexible_values(m, UnservedDemandVariable, "demand__tier1")[19] ≈ 20.0
    @test all(≈(0.0; atol=1e-6), _flexible_values(m, DemandDeferredVariable))
    @test all(≈(0.0; atol=1e-6), _flexible_values(m, DemandRecoveredVariable))
end

@testset "Flexible demand is delayed within its window" begin
    # Hour 19 has no spare gas, so a one-hour delay only works by also delaying 16 MW (the
    # flexible share) of hour 19 to hour 20, and 4 MW of hour 18 is shed
    m = _solved_flexible(_flexible_test_model(; max_demand_delay=1.0))
    @test _flexible_values(m, UnservedDemandVariable, "demand__tier1")[19] ≈ 4.0
    # With two hours the 20 MW are served in hour 20, the first with spare gas
    m = _solved_flexible(_flexible_test_model(; max_demand_delay=2.0))
    unserved = _flexible_values(m, UnservedDemandVariable, "demand__tier1")
    deferred = _flexible_values(m, DemandDeferredVariable)
    recovered = _flexible_values(m, DemandRecoveredVariable)
    @test all(≈(0.0; atol=1e-6), unserved)
    @test deferred[19] ≈ 20.0
    @test recovered[21] ≈ 20.0
    @test sum(deferred) ≈ 20.0
    @test sum(recovered) ≈ 20.0
end

@testset "Flexible demand is advanced within its window" begin
    m = _solved_flexible(_flexible_test_model(; max_demand_advance=2.0))
    unserved = _flexible_values(m, UnservedDemandVariable, "demand__tier1")
    deferred = _flexible_values(m, DemandDeferredVariable)
    recovered = _flexible_values(m, DemandRecoveredVariable)
    backlog = _flexible_values(m, DemandBacklogVariable)
    @test all(≈(0.0; atol=1e-6), unserved)
    @test deferred[19] ≈ 20.0
    # Served in hours 16 and 17, so the backlog is negative before hour 18
    @test recovered[17] + recovered[18] ≈ 20.0
    @test backlog[18] ≈ -20.0
    @test all(≈(0.0; atol=1e-6), recovered[19:24])
end

@testset "Shifting losses increase consumption" begin
    m = _solved_flexible(
        _flexible_test_model(; hour_19=0.5, max_demand_delay=2.0, shift_efficiency=0.8),
    )
    deferred = _flexible_values(m, DemandDeferredVariable)
    recovered = _flexible_values(m, DemandRecoveredVariable)
    @test sum(deferred) ≈ 20.0
    # 20 MWh deferred take 25 MWh to serve, and the backlog closes over the day
    @test sum(recovered) ≈ 25.0
    @test sum(deferred .- 0.8 .* recovered) ≈ 0.0 atol = 1e-6
end

@testset "Flexible demand constraints and costs" begin
    m = _flexible_test_model(;
        max_demand_delay=2.0,
        shift_cost=LinearCurve(5.0),
        max_demand_curtailment=0.1,
        curtailment_cost=LinearCurve(500.0),
    )
    @test _build_status(m) == BUILT
    container = PSIN.get_optimization_container(m)
    variable(type) =
        PSIN.get_variable(container, type(), DEMAND_TYPE, "FlexibleDemandDispatch")
    deferred = variable(DemandDeferredVariable)
    recovered = variable(DemandRecoveredVariable)
    unserved = variable(UnservedDemandVariable)

    # The shift cost is charged once, on deferred demand, with the same weight and
    # discounting as unserved demand
    objective = JuMP.objective_function(PSIN.get_jump_model(container))
    @test JuMP.coefficient(objective, deferred["demand", 19]) / 5.0 ≈
          JuMP.coefficient(objective, unserved["demand__tier2", 19]) / 10_000.0
    @test JuMP.coefficient(objective, recovered["demand", 19]) == 0.0

    # Deferred and unserved demand together are at most the demand
    limit = JuMP.constraint_object(
        PSIN.get_constraint(
            container,
            DemandDeferralLimitConstraint(),
            DEMAND_TYPE,
            "FlexibleDemandDispatch",
        )[
            "demand",
            19,
        ],
    )
    @test JuMP.coefficient(limit.func, deferred["demand", 19]) == 1.0
    @test JuMP.coefficient(limit.func, unserved["demand__tier1", 19]) == 1.0
    @test JuMP.coefficient(limit.func, unserved["demand__tier2", 19]) == 1.0
    @test limit.set.upper ≈ 100.0

    # Bounds: the flexible share of the step's demand and of the day's peak
    @test JuMP.upper_bound(deferred["demand", 1]) ≈ 10.0
    @test JuMP.upper_bound(recovered["demand", 1]) ≈ 20.0
end

@testset "Flexible demand in requirements" begin
    # Coefficient of a flexible demand variable of the first hour in a requirement constraint
    function coefficient(m, constraint_type, requirement_type, name, variable_type)
        container = PSIN.get_optimization_container(m)
        constraint =
            PSIN.get_constraint(container, constraint_type(), requirement_type)[name, 1]
        variable = PSIN.get_variable(
            container,
            variable_type(),
            DEMAND_TYPE,
            "FlexibleDemandDispatch",
        )
        return JuMP.coefficient(
            JuMP.constraint_object(constraint).func,
            variable["demand", 1],
        )
    end

    # The reserve margin credits the net demand shifted out of a step
    m = _flexible_test_model(; max_demand_delay=2.0)
    _attach_requirement!(m, _reserve_margin(), RequirementCapacityReserveMargin)
    @test _build_status(m) == BUILT
    args = (CapacityReserveMarginConstraint, PSIP.CapacityReserveMargin, "reserve_margin")
    @test coefficient(m, args..., DemandDeferredVariable) == 1.0
    @test coefficient(m, args..., DemandRecoveredVariable) == -1.0

    # Hourly matching covers demand where it is served
    m = _flexible_test_model(; max_demand_delay=2.0)
    _attach_requirement!(
        m,
        PSIP.HourlyMatching(; name="hourly_matching", id=2, available=true),
        RequirementHourlyMatching,
    )
    @test _build_status(m) == BUILT
    args = (HourlyMatchingConstraint, PSIP.HourlyMatching, "hourly_matching")
    @test coefficient(m, args..., DemandDeferredVariable) == 1.0
    @test coefficient(m, args..., DemandRecoveredVariable) == -1.0
end

@testset "Flexible demand checks" begin
    flexible(; kwargs...) = _demand("demand"; flexible_fraction=0.2, kwargs...)
    @test_throws r"flexible_fraction" PSIN.check_flexible_demand(
        flexible(; flexible_fraction=1.5),
    )
    @test_throws r"shift_efficiency" PSIN.check_flexible_demand(
        flexible(; max_demand_delay=2.0, shift_efficiency=0.0),
    )
    @test_throws r"windows" PSIN.check_flexible_demand(flexible(; max_demand_delay=-1.0))
    @test_throws r"not supported" PSIN.check_flexible_demand(
        flexible(;
            max_demand_delay=2.0,
            shift_cost=PiecewiseIncrementalCurve(0.0, [0.0, 1.0], [5.0]),
        ),
    )
    @test_logs (:warn, r"none of its demand can be shifted") PSIN.check_flexible_demand(
        flexible(),
    )
    @test_logs PSIN.check_flexible_demand(flexible(; max_demand_advance=1.0))

    # Windows in time steps: 0 forbids shifting, and a window stays within its day
    m = _flexible_test_model()
    @test _build_status(m) == BUILT
    time_mapping = PSIN.get_time_mapping(PSIN.get_optimization_container(m))
    @test PSIN._shift_window(time_mapping, 1, 0.0) == 0
    @test PSIN._shift_window(time_mapping, 1, 2.5) == 3
    @test PSIN._shift_window(time_mapping, 1, 100.0) == 23
end
