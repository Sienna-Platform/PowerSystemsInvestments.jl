const ESR_PERIODS = [
    (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
    (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
]

const ESR_STORAGE_TYPE = PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
const ESR_COLOCATED_TYPE = PSIP.ColocatedSupplyStorageTechnology{PSY.RenewableDispatch}

# Two zone model where wind must supply `fraction` of demand2 in 2030-2034. With `storage`,
# the battery and the co-located technology are also attached to the policy.
function _energy_share_model(
    fraction;
    use_slacks=false,
    duals=Vector{DataType}(),
    attributes=Dict{String, Any}(),
    thermal_investment=ContinuousInvestment,
    storage=false,
    inverter_efficiency=1.0,
)
    p_5bus, op_days = test_2_zone_portfolio()
    wind = PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p_5bus, "wind")
    demand2 = PSIP.get_technology(PSIP.ProjectedDemand{PSY.PowerLoad}, p_5bus, "demand2")
    esr = PSIP.EnergyShareRequirements(;
        name="wind_share",
        id=1,
        available=true,
        target_year=2030,
        generation_fraction_requirement=fraction,
    )
    PSIP.add_requirement!(p_5bus, esr)
    PSIP.set_requirements!(wind, [esr])
    PSIP.set_requirements!(demand2, [esr])
    PSIP.set_inverter_efficiency!(
        PSIP.get_technology(ESR_COLOCATED_TYPE, p_5bus, "colocated_test"),
        inverter_efficiency,
    )
    if storage
        PSIP.set_requirements!(
            PSIP.get_technology(ESR_STORAGE_TYPE, p_5bus, "test_storage"),
            [esr],
        )
        PSIP.set_requirements!(
            PSIP.get_technology(ESR_COLOCATED_TYPE, p_5bus, "colocated_test"),
            [esr],
        )
    end
    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), ESR_PERIODS),
        OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods(Vector{Vector{DateTime}}()),
        TransportModel(MultiRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["demand1", "demand2"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
        StaticLoadInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["wind"],
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["cheap_thermal", "expensive_thermal"],
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        thermal_investment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["test_branch"],
        PSIP.AggregateTransportTechnology{PSY.ACBranch},
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    if storage
        set_technology_model!(
            template,
            ["test_storage"],
            ESR_STORAGE_TYPE,
            ContinuousInvestment,
            CyclicalStorageDispatch,
            BasicDispatchFeasibility,
        )
        set_technology_model!(
            template,
            ["colocated_test"],
            ESR_COLOCATED_TYPE,
            ContinuousInvestment,
            CyclicalColocatedDispatch,
            BasicDispatchFeasibility,
        )
    end
    set_requirement_model!(
        template,
        ["wind_share"],
        RequirementModel(
            PSIP.EnergyShareRequirements,
            RequirementEnergyShare;
            use_slacks=use_slacks,
            duals=duals,
            attributes=attributes,
        ),
    )
    m = InvestmentModel(
        template,
        SingleInstanceSolve,
        p_5bus;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
        store_variable_names=true,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    return m, demand2
end

_objective(m) =
    JuMP.objective_value(PSIN.get_jump_model(PSIN.get_optimization_container(m)))

# Yearly demand2 in the 2030 representative day
function _demand_2030(demand2)
    data =
        IS.get_time_series(
            IS.SingleTimeSeries,
            demand2,
            "ops_demand";
            year="2030",
            rep_day=1,
        ).data
    return 365 * sum(TimeSeries.values(data)) * PSIP.get_peak_demand_mw(demand2)
end

const ESR_KEY =
    PSIN.ConstraintKey(EnergyShareRequirementConstraint, PSIP.EnergyShareRequirements)

@testset "Requirement formulations must match the requirement type" begin
    @test_throws r"RequirementEnergyShare is not a formulation of HourlyMatching. Supported requirement formulations: RequirementHourlyMatching." RequirementModel(
        PSIP.HourlyMatching,
        RequirementEnergyShare,
    )
    @test_throws r"Supported requirement formulations: RequirementCarbonCapMass, RequirementCarbonCapDemandRate, RequirementCarbonCapGenerationRate." RequirementModel(
        PSIP.CarbonCaps,
        RequirementEnergyShare,
    )
    @test RequirementModel(PSIP.EnergyShareRequirements, RequirementEnergyShare) isa
          RequirementModel
end

@testset "Energy share duals" begin
    m, demand2 = _energy_share_model(1.5; duals=[EnergyShareRequirementConstraint])
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    dual = only(read_dual(m, ESR_KEY).value)
    @test dual > 0.0
    # The dual is the cost of one more MWh per year of required generation
    step = 1e-3
    tighter, _ = _energy_share_model(1.5 + step)
    @test solve!(tighter) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test (_objective(tighter) - _objective(m)) / (step * _demand_2030(demand2)) ≈ dual rtol =
        1e-6

    # A MIP's duals are those of the LP with its integer builds fixed, which is restored to
    # a MIP before the next solve
    mip, _ = _energy_share_model(
        1.5;
        duals=[EnergyShareRequirementConstraint],
        thermal_investment=IntegerInvestment,
    )
    @test solve!(mip) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test only(read_dual(mip, ESR_KEY).value) > 0.0
    container = PSIN.get_optimization_container(mip)
    @test !PSIN.is_milp(container)
    PSIN.unfix_discrete_variables!(container)
    @test PSIN.is_milp(container)
end

@testset "Energy share slacks" begin
    infeasible, _ = _energy_share_model(50.0)
    @test solve!(infeasible; console_level=Logging.AboveMaxLevel) == PSIN.RunStatus.FAILED

    penalty = 1e3
    m, demand2 = _energy_share_model(
        50.0;
        use_slacks=true,
        attributes=Dict{String, Any}("slack_penalty" => penalty),
    )
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    container = PSIN.get_optimization_container(m)
    slack = PSIN.get_variable(
        container,
        RequirementSlackVariable(),
        PSIP.EnergyShareRequirements,
    )
    generation = PSIN.get_expression(
        container,
        WeightedEnergyShareGeneration(),
        PSIP.EnergyShareRequirements,
    )
    # The slack covers the shortfall, which costs the penalty in each year of 2030-2034,
    # discounted at 7% to 2025
    @test JuMP.value(slack["wind_share"]) ≈
          50.0 * _demand_2030(demand2) - JuMP.value(generation["wind_share", 1]) rtol = 1e-6
    @test JuMP.coefficient(
        JuMP.objective_function(PSIN.get_jump_model(container)),
        slack["wind_share"],
    ) ≈ penalty * sum(1.07^-k for k in 0:4) * 1.07^-5
    @test only(
        read_variable(
            m,
            PSIN.VariableKey(RequirementSlackVariable, PSIP.EnergyShareRequirements),
        ).value,
    ) ≈ JuMP.value(slack["wind_share"])
end

@testset "Energy share storage losses" begin
    # The co-located technology exchanges energy with the grid through a 90% inverter
    η = 0.9
    m, demand2 = _energy_share_model(1.5; storage=true, inverter_efficiency=η)
    container = PSIN.get_optimization_container(m)
    generation = PSIN.get_expression(
        container,
        WeightedEnergyShareGeneration(),
        PSIP.EnergyShareRequirements,
    )
    demand = PSIN.get_expression(
        container,
        WeightedEnergyShareDemand(),
        PSIP.EnergyShareRequirements,
    )
    variable(variable_type, technology_type, meta) =
        PSIN.get_variable(container, variable_type, technology_type, meta)
    storage_in =
        variable(ActiveInPowerVariable(), ESR_STORAGE_TYPE, "CyclicalStorageDispatch")
    storage_out =
        variable(ActiveOutPowerVariable(), ESR_STORAGE_TYPE, "CyclicalStorageDispatch")
    colocated(variable_type) =
        variable(variable_type, ESR_COLOCATED_TYPE, "CyclicalColocatedDispatch")
    for t in (1, 24)
        # Storage is not eligible generation: its losses, including those of the inverter,
        # are added to the demand, so they are scaled by the required share like the rest of
        # the demand
        for (var, coefficient) in (
            (storage_in["test_storage", t], 365.0),
            (storage_out["test_storage", t], -365.0),
            (colocated(ActivePowerChargeVariable())["colocated_test", t], 365.0 / η),
            (colocated(ActivePowerDischargeVariable())["colocated_test", t], -365.0 * η),
        )
            @test JuMP.coefficient(demand["wind_share", 1], var) ≈ coefficient
            @test JuMP.coefficient(generation["wind_share", 1], var) == 0.0
        end
        # The wind and solar output the co-located technology delivers is eligible generation
        for variable_type in (ActivePowerWindVariable(), ActivePowerSolarVariable())
            var = colocated(variable_type)["colocated_test", t]
            @test JuMP.coefficient(generation["wind_share", 1], var) ≈ 365.0 * η
            @test JuMP.coefficient(demand["wind_share", 1], var) == 0.0
        end
        for var in (
            colocated(ActiveInPowerVariable())["colocated_test", t],
            colocated(ActiveOutPowerVariable())["colocated_test", t],
        )
            @test JuMP.coefficient(generation["wind_share", 1], var) == 0.0
            @test JuMP.coefficient(demand["wind_share", 1], var) == 0.0
        end
    end
    @test JuMP.constant(demand["wind_share", 1]) ≈ _demand_2030(demand2)

    # Grid output is the inverter efficiency times the discharge, wind and solar output, and
    # charging takes the inverter efficiency times the grid input
    balance(meta) = PSIN.get_constraint(
        container,
        PSIN.ColocatedInternalBalanceConstraint(),
        ESR_COLOCATED_TYPE,
        "CyclicalColocatedDispatch_$meta",
    )[
        "colocated_test",
        5,
    ]
    coefficient(con, variable_type) =
        JuMP.normalized_coefficient(con, colocated(variable_type)["colocated_test", 5])
    @test coefficient(balance("out"), ActiveOutPowerVariable()) ≈ 1.0
    for variable_type in (
        ActivePowerDischargeVariable(),
        ActivePowerWindVariable(),
        ActivePowerSolarVariable(),
    )
        @test coefficient(balance("out"), variable_type) ≈ -η
    end
    @test coefficient(balance("in"), ActivePowerChargeVariable()) ≈ 1.0
    @test coefficient(balance("in"), ActiveInPowerVariable()) ≈ -η

    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test JuMP.value(generation["wind_share", 1]) >=
          1.5 * JuMP.value(demand["wind_share", 1]) - 1e-3
end

const CARBON_THERMAL_TYPE = PSIP.SupplyTechnology{PSY.ThermalStandard}
# Heat rate (MMBtu/MWh) and carbon intensity (tCO2/MMBtu) of the thermal technologies
const CARBON_HEAT_RATES = Dict("cheap_thermal" => 10.0, "expensive_thermal" => 8.0)
const CARBON_INTENSITY = 0.1

# Two zone model whose thermal technologies have fuel curves. `requirement` (or nothing) is
# attached to the thermal technologies, wind and `demands`, with `storage` to the battery too,
# and with `line` to the zonal line from Zone_1 to Zone_2, dispatched by `line_operation`.
function _policy_model(
    requirement,
    formulation;
    use_slacks=false,
    duals=Vector{DataType}(),
    storage=false,
    attributes=Dict{String, Any}(),
    demands=["demand1", "demand2"],
    line=false,
    line_operation=BasicDispatch,
    supply=["cheap_thermal", "expensive_thermal", "wind"],
    colocated=false,
)
    p_5bus, op_days = test_2_zone_portfolio()
    for (name, heat_rate) in CARBON_HEAT_RATES
        thermal = PSIP.get_technology(CARBON_THERMAL_TYPE, p_5bus, name)
        PSIP.set_operation_costs!(
            thermal,
            ThermalGenerationCost(;
                variable=FuelCurve(; value_curve=LinearCurve(heat_rate), fuel_cost=3.0),
                fixed=0.0,
                start_up=0.0,
                shut_down=0.0,
            ),
        )
        PSIP.set_co2!(thermal, Dict(ThermalFuels.COAL => CARBON_INTENSITY))
    end
    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), ESR_PERIODS),
        OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods(Vector{Vector{DateTime}}()),
        TransportModel(MultiRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["demand1", "demand2"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
        StaticLoadInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["wind"],
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["cheap_thermal", "expensive_thermal"],
        CARBON_THERMAL_TYPE,
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["test_branch"],
        PSIP.AggregateTransportTechnology{PSY.ACBranch},
        ContinuousInvestment,
        line_operation,
        BasicDispatchFeasibility,
    )
    if storage
        set_technology_model!(
            template,
            ["test_storage"],
            ESR_STORAGE_TYPE,
            ContinuousInvestment,
            CyclicalStorageDispatch,
            BasicDispatchFeasibility,
        )
    end
    if colocated
        set_technology_model!(
            template,
            ["colocated_test"],
            ESR_COLOCATED_TYPE,
            ContinuousInvestment,
            CyclicalColocatedDispatch,
            BasicDispatchFeasibility,
        )
    end
    if !isnothing(requirement)
        PSIP.add_requirement!(p_5bus, requirement)
        supply_type(name) =
            name == "wind" ? PSIP.SupplyTechnology{PSY.RenewableDispatch} :
            CARBON_THERMAL_TYPE
        for (type, name) in [
            [(supply_type(name), name) for name in supply]...,
            [(PSIP.ProjectedDemand{PSY.PowerLoad}, name) for name in demands]...,
            fill((ESR_STORAGE_TYPE, "test_storage"), storage)...,
            fill((ESR_COLOCATED_TYPE, "colocated_test"), colocated)...,
            fill((PSIP.AggregateTransportTechnology{PSY.ACBranch}, "test_branch"), line)...,
        ]
            PSIP.set_requirements!(PSIP.get_technology(type, p_5bus, name), [requirement])
        end
        set_requirement_model!(
            template,
            [PSIP.get_name(requirement)],
            RequirementModel(
                typeof(requirement),
                formulation;
                use_slacks=use_slacks,
                duals=duals,
                attributes=attributes,
            ),
        )
    end
    m = InvestmentModel(
        template,
        SingleInstanceSolve,
        p_5bus;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
        store_variable_names=true,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    return m
end

_carbon_cap(; max_mtons=1e8, max_tons_mwh=1e8) = PSIP.CarbonCaps(;
    name="carbon_cap",
    id=1,
    available=true,
    target_year=2030,
    max_mtons=max_mtons,
    max_tons_mwh=max_tons_mwh,
)

# Yearly 2030-2034 emissions, generation of the thermal technologies and wind, and demand,
# computed from the solution
function _carbon_totals(m)
    container = PSIN.get_optimization_container(m)
    dispatch(type) =
        JuMP.value.(
            PSIN.get_variable(container, PSIN.ActivePowerVariable(), type, "BasicDispatch"),
        )
    thermal = dispatch(CARBON_THERMAL_TYPE)
    wind = dispatch(PSIP.SupplyTechnology{PSY.RenewableDispatch})
    emissions =
        365 * sum(
            CARBON_INTENSITY * heat_rate * sum(thermal[name, t] for t in 1:24) for
            (name, heat_rate) in CARBON_HEAT_RATES
        )
    generation = 365 * (sum(thermal[:, 1:24].data) + sum(wind["wind", t] for t in 1:24))
    demand = sum(
        _demand_2030(
            PSIP.get_technology(
                PSIP.ProjectedDemand{PSY.PowerLoad},
                PSIN.get_portfolio(m),
                name,
            ),
        ) for name in ("demand1", "demand2")
    )
    return (emissions=emissions, generation=generation, demand=demand)
end

@testset "Carbon caps" begin
    uncapped = _carbon_totals(_policy_model(nothing, nothing))
    @test uncapped.emissions > 0.0

    # Each limit is set to half the uncapped emissions, so it binds
    for (formulation, requirement, limit) in (
        (
            RequirementCarbonCapMass,
            _carbon_cap(; max_mtons=0.5 * uncapped.emissions / 1e6),
            totals -> 0.5 * uncapped.emissions,
        ),
        (
            RequirementCarbonCapDemandRate,
            _carbon_cap(; max_tons_mwh=0.5 * uncapped.emissions / uncapped.demand),
            totals -> 0.5 * uncapped.emissions / uncapped.demand * totals.demand,
        ),
        (
            RequirementCarbonCapGenerationRate,
            _carbon_cap(; max_tons_mwh=0.5 * uncapped.emissions / uncapped.generation),
            totals -> 0.5 * uncapped.emissions / uncapped.generation * totals.generation,
        ),
    )
        m = _policy_model(requirement, formulation; duals=[CarbonCapConstraint])
        totals = _carbon_totals(m)
        @test totals.emissions ≈ limit(totals) rtol = 1e-6
        @test totals.emissions < 0.9 * uncapped.emissions

        container = PSIN.get_optimization_container(m)
        meta = string(formulation)
        emissions =
            PSIN.get_expression(container, WeightedCarbonEmissions(), PSIP.CarbonCaps, meta)
        @test JuMP.value(emissions["carbon_cap", 1]) ≈ totals.emissions rtol = 1e-6
        dispatch = PSIN.get_variable(
            container,
            PSIN.ActivePowerVariable(),
            CARBON_THERMAL_TYPE,
            "BasicDispatch",
        )
        # tCO2/MMBtu × MMBtu/MWh × 365 days
        @test JuMP.coefficient(emissions["carbon_cap", 1], dispatch["cheap_thermal", 5]) ≈
              CARBON_INTENSITY * 10.0 * 365
        dual = read_dual(m, PSIN.ConstraintKey(CarbonCapConstraint, PSIP.CarbonCaps, meta))
        @test only(dual.value) < 0.0
    end

    # With slacks, a cap of zero is met by paying for the shortfall
    m = _policy_model(
        _carbon_cap(; max_mtons=0.0),
        RequirementCarbonCapMass;
        use_slacks=true,
    )
    slack = only(
        read_variable(
            m,
            PSIN.VariableKey(
                RequirementSlackVariable,
                PSIP.CarbonCaps,
                "RequirementCarbonCapMass",
            ),
        ).value,
    )
    @test slack ≈ _carbon_totals(m).emissions rtol = 1e-6
    @test slack > 0.0
end

@testset "Carbon tax" begin
    tax = 50.0
    requirement = PSIP.CarbonTax(;
        name="carbon_tax",
        id=1,
        available=true,
        target_year=2030,
        tax_dollars_per_ton=tax,
    )
    taxed = _policy_model(requirement, RequirementCarbonTax)
    untaxed = _policy_model(nothing, nothing)
    coefficient(m, t) = JuMP.coefficient(
        JuMP.objective_function(PSIN.get_jump_model(PSIN.get_optimization_container(m))),
        PSIN.get_variable(
            PSIN.get_optimization_container(m),
            PSIN.ActivePowerVariable(),
            CARBON_THERMAL_TYPE,
            "BasicDispatch",
        )[
            "cheap_thermal",
            t,
        ],
    )
    # The tax is paid on the 2030-2034 emissions, in each of those years, discounted to 2025
    @test coefficient(taxed, 5) - coefficient(untaxed, 5) ≈
          tax * CARBON_INTENSITY * 10.0 * 365 * sum(1.07^-k for k in 0:4) * 1.07^-5
    @test coefficient(taxed, 30) ≈ coefficient(untaxed, 30)
    @test _carbon_totals(taxed).emissions < _carbon_totals(untaxed).emissions

    @test_throws r"RequirementCarbonTax has no constraint to add slacks to" RequirementModel(
        PSIP.CarbonTax,
        RequirementCarbonTax;
        use_slacks=true,
    )
end

@testset "Carbon requirements need technologies with fuel curves" begin
    p_5bus, _ = test_2_zone_portfolio()
    requirement = _carbon_cap()
    PSIP.add_requirement!(p_5bus, requirement)
    PSIP.set_requirements!(
        PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p_5bus, "wind"),
        [requirement],
    )
    @test_throws r"has no available contributing technology with a fuel curve" PSIN._check_emitters(
        p_5bus,
        requirement,
    )
end

_capacity_reserve_margin(fraction) = PSIP.CapacityReserveMargin(;
    name="reserve_margin",
    id=1,
    available=true,
    target_year=2030,
    capacity_reserve_fraction=fraction,
)

# Reserve above the requirement in each 2030 time step, computed from the solution
function _reserve_surplus(m, fraction)
    container = PSIN.get_optimization_container(m)
    p = PSIN.get_portfolio(m)
    capacity(technology) =
        JuMP.value.(
            PSIN.get_expression(
                container,
                PSIN.CumulativeCapacity(),
                technology,
                "ContinuousInvestment",
            ),
        )
    thermal = capacity(CARBON_THERMAL_TYPE)
    wind_type = PSIP.SupplyTechnology{PSY.RenewableDispatch}
    wind = capacity(wind_type)
    series(technology, name) = TimeSeries.values(
        IS.get_time_series(
            IS.SingleTimeSeries,
            technology,
            name;
            year="2030",
            rep_day=1,
        ).data,
    )
    capacity_factor =
        series(PSIP.get_technology(wind_type, p, "wind"), "ops_variable_cap_factor")
    # Demand series are normalized to the peak demand
    demand_mw(d) = series(d, "ops_demand") .* PSIP.get_peak_demand_mw(d)
    demand = sum(
        demand_mw(PSIP.get_technology(PSIP.ProjectedDemand{PSY.PowerLoad}, p, name)) for
        name in ("demand1", "demand2")
    )
    storage(variable_type) =
        JuMP.value.(
            PSIN.get_variable(
                container,
                variable_type,
                ESR_STORAGE_TYPE,
                "CyclicalStorageDispatch",
            ),
        )
    discharge = storage(PSIN.ActiveOutPowerVariable())
    charge = storage(PSIN.ActiveInPowerVariable())
    return [
        thermal["cheap_thermal", 1] +
        thermal["expensive_thermal", 1] +
        capacity_factor[t] * wind["wind", 1] +
        discharge["test_storage", t] - charge["test_storage", t] -
        (1 + fraction) * demand[t] for t in 1:24
    ]
end

@testset "Capacity reserve margin" begin
    unconstrained = _policy_model(nothing, nothing; storage=true)
    @test minimum(_reserve_surplus(unconstrained, 0.3)) < -1.0

    m = _policy_model(
        _capacity_reserve_margin(0.3),
        RequirementCapacityReserveMargin;
        storage=true,
        duals=[CapacityReserveMarginConstraint],
    )
    # The margin is met in every 2030 time step and binds in some
    @test minimum(_reserve_surplus(m, 0.3)) ≈ 0.0 atol = 1e-4
    @test _objective(m) > _objective(unconstrained)

    constraints = PSIN.get_constraint(
        PSIN.get_optimization_container(m),
        CapacityReserveMarginConstraint(),
        PSIP.CapacityReserveMargin,
    )
    @test all(isassigned(constraints.data, 1, t) for t in 1:24)
    @test !any(isassigned(constraints.data, 1, t) for t in 25:48)
    duals =
        sort(
            read_dual(
                m,
                PSIN.ConstraintKey(
                    CapacityReserveMarginConstraint,
                    PSIP.CapacityReserveMargin,
                ),
            ),
            :time_index,
        ).value
    @test all(isnan, duals[25:48])
    @test all(>=(-1e-6), duals[1:24])
    @test maximum(duals[1:24]) > 0.0

    # With slacks cheaper than capacity, the shortfall of each time step is a slack
    m = _policy_model(
        _capacity_reserve_margin(100.0),
        RequirementCapacityReserveMargin;
        storage=true,
        use_slacks=true,
        attributes=Dict{String, Any}("slack_penalty" => 1.0),
    )
    slack =
        JuMP.value.(
            PSIN.get_variable(
                PSIN.get_optimization_container(m),
                RequirementSlackVariable(),
                PSIP.CapacityReserveMargin,
            ),
        )
    @test slack["reserve_margin", 1:24].data ≈ -_reserve_surplus(m, 100.0) rtol = 1e-6
    @test all(iszero, slack["reserve_margin", 25:48].data)
end

# Left side minus right side of a constraint at the solution
_constraint_surplus(constraint) =
    JuMP.value(JuMP.constraint_object(constraint).func) -
    MOI.constant(JuMP.constraint_object(constraint).set)

@testset "Capacity reserve margin with transmission" begin
    line_type = PSIP.AggregateTransportTechnology{PSY.ACBranch}
    for operation in (BasicDispatch, BasicDispatchWithLosses)
        # The area is Zone_2, the region of demand2, which the line from Zone_1 enters
        m = _policy_model(
            _capacity_reserve_margin(0.3),
            RequirementCapacityReserveMargin;
            demands=["demand2"],
            line=true,
            line_operation=operation,
        )
        container = PSIN.get_optimization_container(m)
        constraints = PSIN.get_constraint(
            container,
            CapacityReserveMarginConstraint(),
            PSIP.CapacityReserveMargin,
        )
        meta = string(operation)
        flow(variable_type) =
            JuMP.value.(PSIN.get_variable(container, variable_type, line_type, meta))
        inflow = if operation == BasicDispatch
            [flow(FlowActivePowerVariable())["test_branch", t] for t in 1:24]
        else
            # Flows into Zone_2 arrive net of the 5% losses
            [
                0.95 * flow(FlowActivePowerFromToVariable())["test_branch", t] -
                flow(FlowActivePowerToFromVariable())["test_branch", t] for t in 1:24
            ]
        end
        p = PSIN.get_portfolio(m)
        capacity(technology) =
            JuMP.value.(
                PSIN.get_expression(
                    container,
                    PSIN.CumulativeCapacity(),
                    technology,
                    "ContinuousInvestment",
                ),
            )
        thermal = capacity(CARBON_THERMAL_TYPE)
        wind_type = PSIP.SupplyTechnology{PSY.RenewableDispatch}
        series(technology, name) = TimeSeries.values(
            IS.get_time_series(
                IS.SingleTimeSeries,
                technology,
                name;
                year="2030",
                rep_day=1,
            ).data,
        )
        capacity_factor =
            series(PSIP.get_technology(wind_type, p, "wind"), "ops_variable_cap_factor")
        demand2 = PSIP.get_technology(PSIP.ProjectedDemand{PSY.PowerLoad}, p, "demand2")
        # Demand series are normalized to the peak demand
        demand = series(demand2, "ops_demand") .* PSIP.get_peak_demand_mw(demand2)
        for t in 1:24
            expected =
                thermal["cheap_thermal", 1] +
                thermal["expensive_thermal", 1] +
                capacity_factor[t] * capacity(wind_type)["wind", 1] +
                inflow[t] - 1.3 * demand[t]
            @test _constraint_surplus(constraints["reserve_margin", t]) ≈ expected atol =
                1e-4
        end
        @test any(!iszero, inflow)
    end

    # With both demands attached the area holds both ends of the line
    p_5bus, _ = test_2_zone_portfolio()
    requirement = _capacity_reserve_margin(0.3)
    PSIP.add_requirement!(p_5bus, requirement)
    for (type, name) in (
        (PSIP.ProjectedDemand{PSY.PowerLoad}, "demand1"),
        (PSIP.ProjectedDemand{PSY.PowerLoad}, "demand2"),
        (line_type, "test_branch"),
    )
        PSIP.set_requirements!(PSIP.get_technology(type, p_5bus, name), [requirement])
    end
    @test_logs (:warn, r"test_branch is fully inside the area") PSIN._boundary_lines(
        p_5bus,
        requirement;
        warn=true,
    )
    @test isempty(PSIN._boundary_lines(p_5bus, requirement))
end

_capacity_requirement(type, limit) = type(;
    name="capacity_requirement",
    id=1,
    available=true,
    target_year=2030,
    (type == PSIP.MinimumCapacityRequirements ? :min_capacity_mw : :max_capacity_mw) =>
        limit,
)

# 2030 capacity of the resources a capacity requirement counts, from the solution
function _counted_capacity(m)
    container = PSIN.get_optimization_container(m)
    value(expression_type, technology, name) = JuMP.value(
        PSIN.get_expression(container, expression_type, technology, "ContinuousInvestment")[
            name,
            1,
        ],
    )
    return value(PSIN.CumulativeCapacity(), CARBON_THERMAL_TYPE, "cheap_thermal") +
           value(PSIN.CumulativeCapacity(), CARBON_THERMAL_TYPE, "expensive_thermal") +
           value(
               PSIN.CumulativeCapacity(),
               PSIP.SupplyTechnology{PSY.RenewableDispatch},
               "wind",
           ) +
           value(PSIN.CumulativePowerCapacity(), ESR_STORAGE_TYPE, "test_storage") +
           value(PSIN.CumulativeWindCapacity(), ESR_COLOCATED_TYPE, "colocated_test") +
           value(PSIN.CumulativeSolarCapacity(), ESR_COLOCATED_TYPE, "colocated_test")
end

@testset "Minimum and maximum capacity requirements" begin
    unconstrained =
        _counted_capacity(_policy_model(nothing, nothing; storage=true, colocated=true))
    for (type, formulation, limit) in (
        (
            PSIP.MinimumCapacityRequirements,
            RequirementMinimumCapacity,
            unconstrained + 500.0,
        ),
        (PSIP.MaximumCapacityRequirements, RequirementMaximumCapacity, 0.8 * unconstrained),
    )
        m = _policy_model(
            _capacity_requirement(type, limit),
            formulation;
            storage=true,
            colocated=true,
            duals=[CapacityRequirementConstraint],
        )
        # Supply capacity, storage power and co-located wind and solar capacity count
        @test _counted_capacity(m) ≈ limit rtol = 1e-6
        dual = only(
            read_dual(m, PSIN.ConstraintKey(CapacityRequirementConstraint, type)).value,
        )
        @test abs(dual) > 0.0
    end

    # With slacks, a maximum of zero is exceeded by the capacity built
    m = _policy_model(
        _capacity_requirement(PSIP.MaximumCapacityRequirements, 0.0),
        RequirementMaximumCapacity;
        storage=true,
        colocated=true,
        use_slacks=true,
    )
    slack = only(
        read_variable(
            m,
            PSIN.VariableKey(RequirementSlackVariable, PSIP.MaximumCapacityRequirements),
        ).value,
    )
    @test slack ≈ _counted_capacity(m) rtol = 1e-6
    @test slack > 0.0

    p_5bus, _ = test_2_zone_portfolio()
    requirement = _capacity_requirement(PSIP.MinimumCapacityRequirements, 100.0)
    demand = PSIP.get_technology(PSIP.ProjectedDemand{PSY.PowerLoad}, p_5bus, "demand1")
    @test_logs (
        :warn,
        r"Demand technologies demand1 attached to requirement 'capacity_requirement' do not contribute",
    ) PSIN._warn_ignored_contributors([demand], requirement, "Demand technologies")
end

@testset "Hourly matching" begin
    hourly_matching() = PSIP.HourlyMatching(; name="hourly_matching", id=1, available=true)
    # Wind and the battery must cover demand2 in every hour of both periods
    matched(; kwargs...) = _policy_model(
        hourly_matching(),
        RequirementHourlyMatching;
        supply=["wind"],
        demands=["demand2"],
        storage=true,
        kwargs...,
    )
    function shortfall(m)
        container = PSIN.get_optimization_container(m)
        p = PSIN.get_portfolio(m)
        wind =
            JuMP.value.(
                PSIN.get_variable(
                    container,
                    PSIN.ActivePowerVariable(),
                    PSIP.SupplyTechnology{PSY.RenewableDispatch},
                    "BasicDispatch",
                ),
            )
        storage(variable_type) =
            JuMP.value.(
                PSIN.get_variable(
                    container,
                    variable_type,
                    ESR_STORAGE_TYPE,
                    "CyclicalStorageDispatch",
                ),
            )
        discharge = storage(PSIN.ActiveOutPowerVariable())
        charge = storage(PSIN.ActiveInPowerVariable())
        demand2 = PSIP.get_technology(PSIP.ProjectedDemand{PSY.PowerLoad}, p, "demand2")
        demand =
            vcat(
                [
                    TimeSeries.values(
                        IS.get_time_series(
                            IS.SingleTimeSeries,
                            demand2,
                            "ops_demand";
                            year=year,
                            rep_day=day,
                        ).data,
                    ) for (year, day) in (("2030", 1), ("2035", 2))
                ]...,
            ) .* PSIP.get_peak_demand_mw(demand2)
        return [
            demand[t] - wind["wind", t] - discharge["test_storage", t] +
            charge["test_storage", t] for t in 1:48
        ]
    end
    unconstrained = _policy_model(nothing, nothing; storage=true)
    @test maximum(shortfall(unconstrained)) > 1.0

    m = matched(; duals=[HourlyMatchingConstraint])
    @test maximum(shortfall(m)) ≈ 0.0 atol = 1e-4
    @test _objective(m) > _objective(unconstrained)
    duals =
        read_dual(
            m,
            PSIN.ConstraintKey(HourlyMatchingConstraint, PSIP.HourlyMatching),
        ).value
    @test length(duals) == 48
    @test all(>=(-1e-6), duals)
    @test maximum(duals) > 0.0

    # With cheap slacks the shortfall of each hour is a slack
    m = matched(; use_slacks=true, attributes=Dict{String, Any}("slack_penalty" => 1.0))
    slack =
        JuMP.value.(
            PSIN.get_variable(
                PSIN.get_optimization_container(m),
                RequirementSlackVariable(),
                PSIP.HourlyMatching,
            ),
        )
    @test slack["hourly_matching", :].data ≈ max.(shortfall(m), 0.0) atol = 1e-4
    @test any(>(1.0), slack.data)

    p_5bus, _ = test_2_zone_portfolio()
    line = PSIP.get_technology(
        PSIP.AggregateTransportTechnology{PSY.ACBranch},
        p_5bus,
        "test_branch",
    )
    @test_logs (
        :warn,
        r"Lines test_branch attached to requirement 'hourly_matching' do not contribute",
    ) PSIN._warn_ignored_contributors([line], hourly_matching(), "Lines")
end

@testset "Requirements need contributing technologies" begin
    p_5bus, _ = test_2_zone_portfolio()
    requirement = _capacity_reserve_margin(0.1)
    PSIP.add_requirement!(p_5bus, requirement)
    @test_throws r"Requirement 'reserve_margin' has no available contributing resources or demand technologies." PSIN._check_contributors(
        p_5bus,
        requirement;
        demands=true,
    )
    PSIP.set_requirements!(
        PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p_5bus, "wind"),
        [requirement],
    )
    @test_throws r"has no available contributing demand technologies." PSIN._check_contributors(
        p_5bus,
        requirement;
        demands=true,
    )
    @test isnothing(PSIN._check_contributors(p_5bus, requirement; demands=false))
end

@testset "Inverter efficiency must be in (0, 1]" begin
    p_5bus, _ = test_2_zone_portfolio()
    colocated = PSIP.get_technology(ESR_COLOCATED_TYPE, p_5bus, "colocated_test")
    PSIP.set_inverter_efficiency!(colocated, 0.0)
    @test_throws r"colocated_test has inverter efficiency 0.0, which must be in \(0, 1\]" PSIN.get_inverter_efficiency(
        colocated,
    )
    PSIP.set_inverter_efficiency!(colocated, 0.95)
    @test PSIN.get_inverter_efficiency(colocated) == 0.95
end
