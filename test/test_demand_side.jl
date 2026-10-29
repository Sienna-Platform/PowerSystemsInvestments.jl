const END_USE_TYPE = PSIP.DemandSideTechnology{PSY.PowerLoad}
const END_USE_THERMAL = PSIP.SupplyTechnology{PSY.ThermalStandard}
const END_USE_DAY = collect(DateTime(2030, 1, 1, 0):Hour(1):DateTime(2030, 1, 1, 23))

function _end_use_financial_data()
    return TechnologyFinancialData(;
        capital_recovery_period=30,
        technology_base_year=2025,
        debt_fraction=0.6,
        debt_rate=0.04,
        return_on_equity=0.10,
        tax_rate=0.21,
    )
end

function _end_use_thermal(name, zone, cost, capacity)
    return END_USE_THERMAL(;
        name=name,
        id=1,
        available=true,
        region=[zone],
        power_systems_type="ThermalStandard",
        prime_mover_type=PrimeMovers.CC,
        fuel=[ThermalFuels.NATURAL_GAS],
        capital_costs=PSIP.CapitalCost(LinearCurve(0.0), 0.0),
        operation_costs=ThermalGenerationCost(;
            variable=CostCurve(LinearCurve(cost)),
            fixed=0.0,
            start_up=0.0,
            shut_down=0.0,
        ),
        capacity_limits=(min=capacity, max=capacity),
        outage_factors=(planned=0.0, forced=0.0),
        financial_data=_end_use_financial_data(),
    )
end

# One zone with a 100 MW demand at `demand_shape`, 100 MW of cheap generation at 20 $/MWh
# and 1000 MW of gas at 80 $/MWh, and an electrolyzer (0.05 MWh per unit of product) with the
# given fields and investment formulation. With `existing_load`, the electrolyzer has an
# existing 25 MW load in the base system.
function _end_use_model(;
    demand_shape=fill(0.5, 24),
    investment=ContinuousInvestment,
    existing_load=false,
    price=2.0,
    kwargs...,
)
    sys = PSY.System(100.0)
    set_units_base_system!(sys, "NATURAL_UNITS")
    bus = ACBus(nothing)
    PSY.set_bustype!(bus, PSY.ACBusTypes.REF)
    add_component!(sys, bus)
    load = PowerLoad(nothing)
    PSY.set_name!(load, "existing_electrolyzer")
    PSY.set_bus!(load, bus)
    add_component!(sys, load)
    PSY.set_max_active_power!(load, 25.0)

    portfolio =
        Portfolio(sys; financial_data=PortfolioFinancialData(2025, 0.07, 0.02, 0.04))
    zone = Zone(; name="zone", id=1)
    PSIP.add_region!(portfolio, zone)
    PSIP.add_technology!(portfolio, _end_use_thermal("cheap", zone, 20.0, 100.0))
    PSIP.add_technology!(portfolio, _end_use_thermal("gas", zone, 80.0, 1000.0))

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
    PSIP.add_time_series!(
        portfolio,
        demand,
        SingleTimeSeries(; name="ops_demand", data=TimeArray(END_USE_DAY, demand_shape));
        year="2030",
        rep_day=1,
    )

    electrolyzer = END_USE_TYPE(;
        name="electrolyzer",
        id=3,
        available=true,
        region=[zone],
        power_systems_type="PowerLoad",
        technology_efficiency=0.05,
        price_per_unit=LinearCurve(price),
        financial_data=_end_use_financial_data(),
        kwargs...,
    )
    PSIP.add_technology!(portfolio, electrolyzer)
    if existing_load
        PSIP.add_supplemental_attribute!(
            portfolio,
            electrolyzer,
            PSIP.ExistingDevices(; existing_devices=["existing_electrolyzer"]),
        )
    end

    template = InvestmentModelTemplate(
        DiscountedCashFlow(
            0.07,
            Year(2025),
            [(Date(Month(1), Year(2030)), Date(Month(12), Year(2030)))],
        ),
        OperationalRepresentativeDays([END_USE_DAY], [365]),
        RepresentativePeriods(Vector{Vector{DateTime}}()),
        TransportModel(SingleRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["cheap", "gas"],
        END_USE_THERMAL,
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
    set_technology_model!(
        template,
        ["electrolyzer"],
        END_USE_TYPE,
        investment,
        EndUseDispatch,
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

# A fixed 30 MW electrolyzer
_fixed_end_use_model(; kwargs...) = _end_use_model(;
    capacity_limits=(min=30.0, max=30.0),
    capital_costs=PSIP.CapitalCost(LinearCurve(0.0), 0.0),
    kwargs...,
)

function _end_use_build_status(m)
    return build!(
        m;
        output_dir=mktempdir(; cleanup=true),
        console_level=Logging.AboveMaxLevel,
    )
end

function _solve_end_use(m)
    @test _end_use_build_status(m) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    return m
end

_end_use_variable(m, type, meta) =
    PSIN.get_variable(PSIN.get_optimization_container(m), type(), END_USE_TYPE, meta)

consumption(m) = [
    JuMP.value(
        _end_use_variable(m, ActiveInPowerVariable, "EndUseDispatch")["electrolyzer", t],
    ) for t in 1:24
]
built(m, meta="ContinuousInvestment") =
    JuMP.value(_end_use_variable(m, BuildCapacity, meta)["electrolyzer", 1])

@testset "End-use dispatch follows the value of its product" begin
    # 2 $/unit at 0.05 MWh/unit is worth 40 $/MWh: above the cheap generation (20) but not the
    # gas (80), and 50 MW of cheap generation is spare
    @test all(≈(30.0), consumption(_solve_end_use(_fixed_end_use_model())))
    # Worth 10 $/MWh: not worth running
    @test all(
        ≈(0.0; atol=1e-6),
        consumption(_solve_end_use(_fixed_end_use_model(; price=0.5))),
    )
    # Worth 100 $/MWh: worth running on gas too
    m = _solve_end_use(_fixed_end_use_model(; price=5.0, demand_shape=fill(1.0, 24)))
    @test all(≈(30.0), consumption(m))
    # A variable cost of 25 $/MWh leaves 15 $/MWh, less than the cheap generation costs
    m = _solve_end_use(
        _fixed_end_use_model(;
            operation_costs=PSY.LoadCost(CostCurve(LinearCurve(25.0)), 0.0),
        ),
    )
    @test all(≈(0.0; atol=1e-6), consumption(m))
end

@testset "End-use minimum power and ramps" begin
    # Not worth running, but at least half of its capacity is always on
    m = _solve_end_use(_fixed_end_use_model(; price=0.5, min_power=0.5))
    @test all(≈(15.0), consumption(m))

    # Cheap generation is spare in hours 0-11 only, so consumption is worth it then. With
    # ramps of 25% of capacity per hour it can't jump between 0 and 30 MW: it changes by at most
    # 7.5 MW between steps (also across the wrap of the day) and passes intermediate values
    shape = [h < 12 ? 0.5 : 1.0 for h in 0:23]
    m = _solve_end_use(
        _fixed_end_use_model(; demand_shape=shape, ramp_limits=(up=0.25, down=0.25)),
    )
    load = consumption(m)
    @test all(abs(load[t] - load[mod1(t - 1, 24)]) <= 7.5 + 1e-6 for t in 1:24)
    @test maximum(load) ≈ 30.0
    @test any(0.1 < l < 29.9 for l in load)
end

@testset "End-use investment" begin
    # A cheap electrolyzer is built up to the spare cheap generation (50 MW); an expensive one
    # is not worth building
    cheap = PSIP.CapitalCost(LinearCurve(1e4), 0.0)
    @test built(_solve_end_use(_end_use_model(; capital_costs=cheap))) ≈ 50.0
    expensive = PSIP.CapitalCost(LinearCurve(1e7), 0.0)
    @test built(_solve_end_use(_end_use_model(; capital_costs=expensive))) ≈ 0.0 atol = 1e-6
    # A fixed cost per MW-year above its margin also stops the build
    m = _solve_end_use(
        _end_use_model(;
            capital_costs=cheap,
            operation_costs=PSY.LoadCost(CostCurve(LinearCurve(0.0)), 1e6),
        ),
    )
    @test built(m) ≈ 0.0 atol = 1e-6
    # Integer investment builds whole 20 MW units: three, since the third still runs 10 MW on
    # spare cheap generation
    m = _solve_end_use(
        _end_use_model(; capital_costs=cheap, unit_size=20.0, investment=IntegerInvestment),
    )
    @test built(m, "IntegerInvestment") ≈ 3.0
    @test all(≈(50.0), consumption(m))
    # The capacity limits apply to existing plus built capacity
    m = _solve_end_use(
        _end_use_model(;
            capital_costs=cheap,
            existing_load=true,
            capacity_limits=(min=0.0, max=40.0),
        ),
    )
    @test built(m) ≈ 15.0
    @test all(≈(40.0), consumption(m))
end

@testset "End-use costs and revenue in the objective" begin
    m = _fixed_end_use_model(;
        operation_costs=PSY.LoadCost(CostCurve(LinearCurve(5.0)), 0.0),
    )
    @test _end_use_build_status(m) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    container = PSIN.get_optimization_container(m)
    objective = JuMP.objective_function(PSIN.get_jump_model(container))
    load = _end_use_variable(m, ActiveInPowerVariable, "EndUseDispatch")["electrolyzer", 1]
    cheap = PSIN.get_variable(
        container,
        ActivePowerVariable(),
        END_USE_THERMAL,
        "BasicDispatch",
    )[
        "cheap",
        1,
    ]
    # The variable cost (5) less the value of the product (40), relative to the cheap
    # generation (20), with the same weighting and discounting
    @test JuMP.coefficient(objective, load) / JuMP.coefficient(objective, cheap) ≈
          (5.0 - 40.0) / 20.0
    # Revenue is kept in its own expression
    revenue =
        PSIN.get_expression(container, ProductRevenue(), END_USE_TYPE, "EndUseDispatch")
    @test JuMP.coefficient(revenue["electrolyzer", 1], load) ≈
          -40.0 / 20.0 * JuMP.coefficient(objective, cheap)
end

@testset "End-use technologies in requirements" begin
    coefficient(m, constraint_type, requirement_type, name) = JuMP.coefficient(
        JuMP.constraint_object(
            PSIN.get_constraint(
                PSIN.get_optimization_container(m),
                constraint_type(),
                requirement_type,
            )[
                name,
                1,
            ],
        ).func,
        _end_use_variable(m, ActiveInPowerVariable, "EndUseDispatch")["electrolyzer", 1],
    )
    function attach!(m, requirement, formulation, names)
        p = PSIN.get_portfolio(m)
        PSIP.add_requirement!(p, requirement)
        for (type, name) in names
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

    # Hourly matching with only the electrolyzer as demand: its consumption must be matched
    m = _fixed_end_use_model()
    attach!(
        m,
        PSIP.HourlyMatching(; name="matching", id=1, available=true),
        RequirementHourlyMatching,
        ((END_USE_THERMAL, "cheap"), (END_USE_TYPE, "electrolyzer")),
    )
    m = _solve_end_use(m)
    @test coefficient(m, HourlyMatchingConstraint, PSIP.HourlyMatching, "matching") == -1.0

    # The energy share counts its consumption on the demand side, weighted by the hours of the
    # year each step stands for (365 for one representative day)
    m = _fixed_end_use_model()
    attach!(
        m,
        PSIP.EnergyShareRequirements(;
            name="share",
            id=3,
            available=true,
            target_year=2030,
            generation_fraction_requirement=0.1,
        ),
        RequirementEnergyShare,
        ((END_USE_THERMAL, "cheap"), (END_USE_TYPE, "electrolyzer")),
    )
    @test _end_use_build_status(m) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    share_demand = PSIN.get_expression(
        PSIN.get_optimization_container(m),
        WeightedEnergyShareDemand(),
        PSIP.EnergyShareRequirements,
    )
    @test JuMP.coefficient(
        share_demand["share", 1],
        _end_use_variable(m, ActiveInPowerVariable, "EndUseDispatch")["electrolyzer", 1],
    ) ≈ 365.0

    # A minimum capacity requirement on the electrolyzer alone forces it to be built
    m = _end_use_model(; capital_costs=PSIP.CapitalCost(LinearCurve(1e7), 0.0))
    attach!(
        m,
        PSIP.MinimumCapacityRequirements(;
            name="electrolyzer_target",
            id=2,
            available=true,
            target_year=2030,
            min_capacity_mw=35.0,
        ),
        RequirementMinimumCapacity,
        ((END_USE_TYPE, "electrolyzer"),),
    )
    @test built(_solve_end_use(m)) ≈ 35.0
end

@testset "End-use checks" begin
    end_use(; kwargs...) = END_USE_TYPE(;
        name="electrolyzer",
        id=1,
        available=true,
        power_systems_type="PowerLoad",
        financial_data=_end_use_financial_data(),
        capacity_limits=(min=0.0, max=50.0),
        kwargs...,
    )
    @test_throws r"technology_efficiency" PSIN.check_end_use(
        end_use(; technology_efficiency=0.0),
    )
    @test_throws r"min_power" PSIN.check_end_use(end_use(; min_power=1.5))
    @test_throws r"not supported" PSIN.check_end_use(
        end_use(; price_per_unit=PiecewiseIncrementalCurve(0.0, [0.0, 1.0], [2.0])),
    )
    @test_logs (:warn, r"no maximum capacity") PSIN.check_end_use(
        end_use(; price_per_unit=LinearCurve(2.0), capacity_limits=(min=0.0, max=1e8)),
    )
    @test_logs PSIN.check_end_use(end_use(; price_per_unit=LinearCurve(2.0)))
end
