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
)
    p_5bus, op_days = test_2_zone_portfolio()
    wind = PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p_5bus, "wind")
    demand2 = PSIP.get_technology(PSIP.DemandRequirement{PSY.PowerLoad}, p_5bus, "demand2")
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
        TransportModel(MultiRegionBalanceModel, use_slacks=false),
    )
    set_technology_model!(
        template,
        ["demand1", "demand2"],
        PSIP.DemandRequirement{PSY.PowerLoad},
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
    return 365 * sum(TimeSeries.values(data))
end

const ESR_KEY =
    PSIN.ConstraintKey(EnergyShareRequirementConstraint, PSIP.EnergyShareRequirements)

@testset "Requirement formulations must match the requirement type" begin
    @test_throws r"RequirementEnergyShare is not a formulation of CapacityReserveMargin. Supported requirement formulations: none." RequirementModel(
        PSIP.CapacityReserveMargin,
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
    m, demand2 = _energy_share_model(1.5; storage=true)
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
        # Storage is not eligible generation: its losses are added to the demand, so they
        # are scaled by the required share like the rest of the demand
        for (var, coefficient) in (
            (storage_in["test_storage", t], 365.0),
            (storage_out["test_storage", t], -365.0),
            (colocated(ActivePowerChargeVariable())["colocated_test", t], 365.0),
            (colocated(ActivePowerDischargeVariable())["colocated_test", t], -365.0),
        )
            @test JuMP.coefficient(demand["wind_share", 1], var) ≈ coefficient
            @test JuMP.coefficient(generation["wind_share", 1], var) == 0.0
        end
        # The wind and solar output of the co-located technology is eligible generation
        for variable_type in (ActivePowerWindVariable(), ActivePowerSolarVariable())
            var = colocated(variable_type)["colocated_test", t]
            @test JuMP.coefficient(generation["wind_share", 1], var) ≈ 365.0
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

    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test JuMP.value(generation["wind_share", 1]) >=
          1.5 * JuMP.value(demand["wind_share", 1]) - 1e-3
end

const CARBON_THERMAL_TYPE = PSIP.SupplyTechnology{PSY.ThermalStandard}
# Heat rate (MMBtu/MWh) and carbon intensity (tCO2/MMBtu) of the thermal technologies
const CARBON_HEAT_RATES = Dict("cheap_thermal" => 10.0, "expensive_thermal" => 8.0)
const CARBON_INTENSITY = 0.1

# Two zone model whose thermal technologies have fuel curves. `requirement` (built from the
# portfolio, or nothing) is attached to the thermal technologies, wind and both demands.
function _carbon_model(requirement, formulation; use_slacks=false, duals=Vector{DataType}())
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
        TransportModel(MultiRegionBalanceModel, use_slacks=false),
    )
    set_technology_model!(
        template,
        ["demand1", "demand2"],
        PSIP.DemandRequirement{PSY.PowerLoad},
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
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    if !isnothing(requirement)
        PSIP.add_requirement!(p_5bus, requirement)
        for (type, name) in (
            (CARBON_THERMAL_TYPE, "cheap_thermal"),
            (CARBON_THERMAL_TYPE, "expensive_thermal"),
            (PSIP.SupplyTechnology{PSY.RenewableDispatch}, "wind"),
            (PSIP.DemandRequirement{PSY.PowerLoad}, "demand1"),
            (PSIP.DemandRequirement{PSY.PowerLoad}, "demand2"),
        )
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
                PSIP.DemandRequirement{PSY.PowerLoad},
                PSIN.get_portfolio(m),
                name,
            ),
        ) for name in ("demand1", "demand2")
    )
    return (emissions=emissions, generation=generation, demand=demand)
end

@testset "Carbon caps" begin
    uncapped = _carbon_totals(_carbon_model(nothing, nothing))
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
        m = _carbon_model(requirement, formulation; duals=[CarbonCapConstraint])
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
    m = _carbon_model(
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
    taxed = _carbon_model(requirement, RequirementCarbonTax)
    untaxed = _carbon_model(nothing, nothing)
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
    @test_throws r"has no available contributing technology with a fuel curve" PSIN._validate_carbon_requirements(
        p_5bus,
        [requirement],
        RequirementCarbonCapMass,
    )
end
