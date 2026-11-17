const TIME_STEP_TEST_PERIODS = [
    (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
    (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
]

function _time_step_test_days(step_hours::Int)
    return [
        collect(DateTime(year, 1, 1, 0):Hour(step_hours):DateTime(year, 1, 1, 23)) for
        year in (2030, 2035)
    ]
end

@testset "Time step length and previous time step" begin
    no_feasibility = Vector{Vector{DateTime}}()
    hourly =
        PSIN.TimeMapping(TIME_STEP_TEST_PERIODS, _time_step_test_days(1), no_feasibility)
    two_hourly =
        PSIN.TimeMapping(TIME_STEP_TEST_PERIODS, _time_step_test_days(2), no_feasibility)

    @test PSIN.get_time_step_length(hourly, 1) == 1.0
    @test PSIN.get_time_step_length(two_hourly, 1) == 2.0
    @test PSIN.get_time_step_length(two_hourly, 2) == 2.0

    # Sub-hourly steps and periods with a single time step.
    half_hourly_day =
        collect(DateTime(2030, 1, 1, 0):Minute(30):DateTime(2030, 1, 1, 23, 30))
    single_step = [DateTime(2035, 1, 1, 0)]
    mixed = PSIN.TimeMapping(
        TIME_STEP_TEST_PERIODS,
        [half_hourly_day, single_step],
        no_feasibility,
    )
    @test PSIN.get_time_step_length(mixed, 1) == 0.5
    @test PSIN.get_time_step_length(mixed, 2) == 1.0

    # Time stamps must be evenly spaced within a representative period.
    uneven_day = [DateTime(2030, 1, 1, 0), DateTime(2030, 1, 1, 1), DateTime(2030, 1, 1, 3)]
    @test_throws ErrorException PSIN.TimeMapping(
        TIME_STEP_TEST_PERIODS,
        [uneven_day, single_step],
        no_feasibility,
    )

    # The second day of the 2-hour mapping covers time steps 13:24.
    @test PSIN.get_previous_time_step(two_hourly, 1, 5) == 4
    @test PSIN.get_previous_time_step(two_hourly, 2, 14) == 13
    # Representative periods are cyclic.
    @test PSIN.get_previous_time_step(two_hourly, 1, 1) == 12
    @test PSIN.get_previous_time_step(two_hourly, 2, 13) == 24
    @test PSIN.get_previous_time_step(two_hourly, 2, 14, 3) == 23
    @test PSIN.get_previous_time_step(two_hourly, 2, 14, 0) == 14
    @test PSIN.get_previous_time_step(mixed, 2, 49) == 49

    # Minimum up and down times are rounded up to a whole number of time steps, at least one.
    @test PSIN.get_commitment_time_steps(hourly, 1, 3.0) == 3
    @test PSIN.get_commitment_time_steps(two_hourly, 1, 3.0) == 2
    @test PSIN.get_commitment_time_steps(two_hourly, 1, 4.0) == 2
    @test PSIN.get_commitment_time_steps(two_hourly, 1, 0.5) == 1
    @test PSIN.get_commitment_time_steps(two_hourly, 1, 0.0) == 1
    @test PSIN.get_commitment_time_steps(two_hourly, 1, 100.0) == 50
    # Exact multiples of the time step do not round up an extra step.
    @test PSIN.get_commitment_time_steps(mixed, 1, 0.9 + 0.6) == 3
end

# One zone with a gas technology defined by a fuel curve, wind, storage and a demand. The
# profiles are constant over blocks of two hours, so a model with hourly time steps and a
# model with 2-hour time steps describe the same system. The gas technology uses the given
# operation formulation. Its commitment data is only used by the commitment formulation.
function _time_step_test_model(step_hours::Int, gas_formulation=BasicDispatch)
    days = _time_step_test_days(step_hours)
    steps_per_block = 2 ÷ step_hours
    blocks = 0:11
    load_blocks = [500.0 + 250.0 * exp(-((b - 9)^2) / 6) for b in blocks]
    wind_blocks = [0.35 + 0.2 * cos(2 * pi * b / 12) for b in blocks]
    load_profile = repeat(load_blocks; inner=steps_per_block)
    wind_profile = repeat(wind_blocks; inner=steps_per_block)

    financial_data() = TechnologyFinancialData(;
        capital_recovery_period=30,
        technology_base_year=2025,
        debt_fraction=0.6,
        debt_rate=0.04,
        return_on_equity=0.10,
        tax_rate=0.21,
    )
    zone = Zone(; name="Zone_1", id=1)
    gas = SupplyTechnology{ThermalStandard}(;
        name="gas",
        id=1,
        available=true,
        region=[zone],
        power_systems_type="ThermalStandard",
        prime_mover_type=PrimeMovers.CC,
        fuel=[ThermalFuels.NATURAL_GAS],
        capital_costs=PSIP.CapitalCost(LinearCurve(1_100_000.0), 0.0),
        operation_costs=ThermalGenerationCost(;
            variable=FuelCurve(;
                value_curve=LinearCurve(7.0, 1.5),
                fuel_cost=5.0,
                vom_cost=LinearCurve(2.0),
                startup_fuel_offtake=LinearCurve(3.0),
            ),
            fixed=15_000.0,
            start_up=40.0,
            shut_down=10.0,
        ),
        capacity_limits=(min=0.0, max=5_000.0),
        financial_data=financial_data(),
        min_generation_fraction=0.4,
        time_limits=(up=4.0, down=2.0),
        ramp_limits=(up=0.3, down=0.3),
    )
    wind = SupplyTechnology{RenewableDispatch}(;
        name="wind",
        id=2,
        available=true,
        region=[zone],
        power_systems_type="RenewableDispatch",
        prime_mover_type=PrimeMovers.WT,
        fuel=[ThermalFuels.OTHER],
        capital_costs=PSIP.CapitalCost(LinearCurve(1_100_000.0), 0.0),
        operation_costs=ThermalGenerationCost(;
            variable=CostCurve(LinearCurve(0.0)),
            fixed=20_000.0,
            start_up=0.0,
            shut_down=0.0,
        ),
        capacity_limits=(min=0.0, max=5_000.0),
        financial_data=financial_data(),
    )
    storage = StorageTechnology{EnergyReservoirStorage}(;
        name="battery",
        id=3,
        available=true,
        region=[zone],
        power_systems_type="EnergyReservoirStorage",
        prime_mover_type=PrimeMovers.BT,
        storage_tech=StorageTech.LIB,
        capacity_limits_discharge=(min=0.0, max=1_000.0),
        capacity_limits_energy=(min=0.0, max=8_000.0),
        efficiency=(in=0.9, out=0.9),
        capital_costs_storage=PSIP.StorageCapitalCost(;
            charge_capital_cost=LinearCurve(0.0),
            discharge_capital_cost=LinearCurve(200_000.0),
            energy_capital_cost=LinearCurve(100_000.0),
            interconnection_cost=0.0,
        ),
        operation_costs=StorageCost(;
            charge_variable_cost=CostCurve(LinearCurve(0.0)),
            discharge_variable_cost=CostCurve(LinearCurve(1.0)),
            fixed=0.0,
        ),
        financial_data=financial_data(),
    )
    demand = DemandRequirement{PowerLoad}(;
        name="demand",
        id=4,
        available=true,
        region=[zone],
        power_systems_type="PowerLoad",
        value_of_lost_load=0.0,
    )

    portfolio = Portfolio(2025, 0.07, 0.02, 0.04)
    PSIP.add_region!(portfolio, zone)
    for technology in (gas, wind, storage, demand)
        PSIP.add_technology!(portfolio, technology)
    end
    for (rep_day, time_stamps) in enumerate(days)
        year = string(Dates.year(first(time_stamps)))
        PSIP.add_time_series!(
            portfolio,
            demand,
            SingleTimeSeries(;
                name="ops_demand",
                data=TimeArray(time_stamps, load_profile),
            );
            year=year,
            rep_day=rep_day,
        )
        PSIP.add_time_series!(
            portfolio,
            wind,
            SingleTimeSeries(;
                name="ops_variable_cap_factor",
                data=TimeArray(time_stamps, wind_profile),
            );
            year=year,
            rep_day=rep_day,
        )
    end

    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), TIME_STEP_TEST_PERIODS),
        OperationalRepresentativeDays(days, [365, 365]),
        RepresentativePeriods(Vector{Vector{DateTime}}()),
        TransportModel(SingleRegionBalanceModel, use_slacks=false),
    )
    set_technology_model!(
        template,
        ["demand"],
        PSIP.DemandRequirement{PSY.PowerLoad},
        StaticLoadInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["gas"],
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        ContinuousInvestment,
        gas_formulation,
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
        ["battery"],
        PSIP.StorageTechnology{EnergyReservoirStorage},
        ContinuousInvestment,
        CyclicalStorageDispatch,
        BasicDispatchFeasibility,
    )
    m = InvestmentModel(
        template,
        SingleInstanceSolve,
        portfolio;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
        store_variable_names=true,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    return m
end

@testset "Models with time steps of different length" begin
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    storage_type = PSIP.StorageTechnology{EnergyReservoirStorage}
    m_hourly = _time_step_test_model(1)
    m_two_hourly = _time_step_test_model(2)
    hourly = PSIN.get_optimization_container(m_hourly)
    two_hourly = PSIN.get_optimization_container(m_two_hourly)

    # The weights describe one year in both models.
    @test_logs min_level = Logging.Warn PSIN.check_operational_weights(
        PSIN.get_time_mapping(two_hourly),
        [365.0, 365.0],
    )
    @test PSIN.get_time_step_weight(hourly, 1) == 365.0
    @test PSIN.get_time_step_weight(two_hourly, 1) == 730.0
    # Costs per MWh are weighted by hours. Costs of starting up or shutting down capacity are
    # per event, so they do not depend on the length of the time step.
    @test PSIN.get_cost_weight(two_hourly, PSIN.ActivePowerVariable(), 1) == 730.0
    @test PSIN.get_cost_weight(two_hourly, PSIN.CommittedCapacityVariable(), 1) == 730.0
    @test PSIN.get_cost_weight(two_hourly, PSIN.StartUpCapacityVariable(), 1) == 365.0
    @test PSIN.get_cost_weight(two_hourly, PSIN.ShutDownCapacityVariable(), 1) == 365.0

    # A MW dispatched during a 2-hour time step costs and burns twice as much as during a
    # 1-hour time step.
    dispatch(container) = PSIN.get_variable(
        container,
        PSIN.ActivePowerVariable(),
        thermal_type,
        "BasicDispatch",
    )
    objective(container) = JuMP.objective_function(PSIN.get_jump_model(container))
    fuel(container) = PSIN.get_expression(
        container,
        FuelConsumptionExpression(),
        thermal_type,
        "BasicDispatch",
    )
    @test JuMP.coefficient(objective(two_hourly), dispatch(two_hourly)["gas", 1]) ≈
          2.0 * JuMP.coefficient(objective(hourly), dispatch(hourly)["gas", 1])
    @test JuMP.coefficient(fuel(hourly)["gas", 1], dispatch(hourly)["gas", 1]) == 7.0
    @test JuMP.coefficient(fuel(two_hourly)["gas", 1], dispatch(two_hourly)["gas", 1]) ==
          14.0

    # Charging during a 2-hour time step stores twice the energy.
    charge(container) = PSIN.get_variable(
        container,
        PSIN.ActiveInPowerVariable(),
        storage_type,
        "CyclicalStorageDispatch",
    )
    balance(container) = PSIN.get_constraint(
        container,
        PSIN.EnergyBalanceConstraint(),
        storage_type,
        "CyclicalStorageDispatch",
    )
    @test JuMP.normalized_coefficient(
        balance(two_hourly)["battery", 2],
        charge(two_hourly)["battery", 2],
    ) ≈
          2.0 * JuMP.normalized_coefficient(
        balance(hourly)["battery", 2],
        charge(hourly)["battery", 2],
    )

    # Both models describe the same system, so they have the same cost, build the same
    # capacity and see the same energy.
    @test solve!(m_hourly) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test solve!(m_two_hourly) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test JuMP.objective_value(PSIN.get_jump_model(two_hourly)) ≈
          JuMP.objective_value(PSIN.get_jump_model(hourly)) rtol = 1e-6

    for key in (
        PSIN.ExpressionKey(CumulativeCapacity, thermal_type, "ContinuousInvestment"),
        PSIN.ExpressionKey(
            CumulativeCapacity,
            PSIP.SupplyTechnology{PSY.RenewableDispatch},
            "ContinuousInvestment",
        ),
        PSIN.ExpressionKey(WeightedEnergyDemand, PSIP.Portfolio),
        PSIN.ExpressionKey(WeightedEnergyGeneration, thermal_type, "BasicDispatch"),
    )
        hourly_df = sort!(read_expression(m_hourly, key), [:name, :time_index])
        two_hourly_df = sort!(read_expression(m_two_hourly, key), [:name, :time_index])
        @test two_hourly_df.value ≈ hourly_df.value rtol = 1e-5
    end

    fuel_key = PSIN.ExpressionKey(FuelConsumptionExpression, thermal_type, "BasicDispatch")
    @test sum(read_expression(m_two_hourly, fuel_key).value) ≈
          sum(read_expression(m_hourly, fuel_key).value) rtol = 1e-5
end

@testset "Thermal commitment with time steps of different length" begin
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    meta = string(ContinuousThermalCommitment)
    m_hourly = _time_step_test_model(1, ContinuousThermalCommitment)
    m_two_hourly = _time_step_test_model(2, ContinuousThermalCommitment)
    hourly = PSIN.get_optimization_container(m_hourly)
    two_hourly = PSIN.get_optimization_container(m_two_hourly)
    variable(container, variable_type, t=1) =
        PSIN.get_variable(container, variable_type, thermal_type, meta)["gas", t]
    constraint(container, constraint_type, constraint_meta=meta) =
        PSIN.get_constraint(container, constraint_type, thermal_type, constraint_meta)[
            "gas",
            1,
        ]
    fuel(container) =
        PSIN.get_expression(container, FuelConsumptionExpression(), thermal_type, meta)[
            "gas",
            1,
        ]
    objective_coefficient(container, variable_type) = JuMP.coefficient(
        JuMP.objective_function(PSIN.get_jump_model(container)),
        variable(container, variable_type),
    )
    coefficient = JuMP.normalized_coefficient
    committed = PSIN.CommittedCapacityVariable()
    start_up = PSIN.StartUpCapacityVariable()
    shut_down = PSIN.ShutDownCapacityVariable()

    # Dispatch and the no-load cost of committed capacity are per hour, so they cost twice as
    # much during a 2-hour time step. Start-up and shut-down costs are per event.
    for variable_type in (PSIN.ActivePowerVariable(), committed)
        @test objective_coefficient(two_hourly, variable_type) ≈
              2.0 * objective_coefficient(hourly, variable_type)
    end
    for variable_type in (start_up, shut_down)
        @test objective_coefficient(hourly, variable_type) > 0.0
        @test objective_coefficient(two_hourly, variable_type) ≈
              objective_coefficient(hourly, variable_type)
    end

    # No-load fuel is burned per hour committed, start-up fuel once per MW started.
    @test JuMP.coefficient(fuel(hourly), variable(hourly, committed)) == 1.5
    @test JuMP.coefficient(fuel(two_hourly), variable(two_hourly, committed)) == 3.0
    @test JuMP.coefficient(fuel(hourly), variable(hourly, start_up)) == 3.0
    @test JuMP.coefficient(fuel(two_hourly), variable(two_hourly, start_up)) == 3.0

    # Committed capacity can ramp by 0.3 of its capacity per hour.
    ramp_up(container) = constraint(container, PSIN.RampRateConstraint(), "$(meta)_up")
    @test coefficient(ramp_up(hourly), variable(hourly, committed)) ≈ -0.3
    @test coefficient(ramp_up(two_hourly), variable(two_hourly, committed)) ≈ -0.6

    # The 4-hour minimum up time covers 4 hourly time steps or 2 time steps of 2 hours, and
    # the 2-hour minimum down time covers 2 hourly time steps or a single time step.
    min_up(container) = constraint(container, PSIN.MinimumUpTimeConstraint())
    min_down(container) = constraint(container, PSIN.MinimumDownTimeConstraint())
    @test coefficient(min_up(hourly), variable(hourly, start_up, 22)) == -1.0
    @test coefficient(min_up(hourly), variable(hourly, start_up, 21)) == 0.0
    @test coefficient(min_up(two_hourly), variable(two_hourly, start_up, 12)) == -1.0
    @test coefficient(min_up(two_hourly), variable(two_hourly, start_up, 11)) == 0.0
    @test coefficient(min_down(hourly), variable(hourly, shut_down, 24)) == 1.0
    @test coefficient(min_down(two_hourly), variable(two_hourly, shut_down, 12)) == 0.0

    @test solve!(m_hourly) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test solve!(m_two_hourly) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
end
