@testset "Objective Function" begin
    test_obj = PSIN.ObjectiveFunction()
    @test PSIN.get_capital_terms(test_obj) == zero(AffExpr)
    @test PSIN.get_operation_terms(test_obj) == zero(AffExpr)
    @test PSIN.get_objective_expression(test_obj) == zero(AffExpr)
    @test PSIN.get_sense(test_obj) == JuMP.MOI.MIN_SENSE

    test_obj = PSIN.ObjectiveFunction()
    PSIN.add_to_capital_terms(test_obj, 10.0)
    m = JuMP.Model()
    x = JuMP.@variable(m)
    PSIN.add_to_capital_terms(test_obj, 5.0 * x)
    @test PSIN.get_capital_terms(test_obj) == 5.0 * x + 10.0

    PSIN.add_to_operation_terms(test_obj, 50.0)
    y = JuMP.@variable(m)
    PSIN.add_to_operation_terms(test_obj, 10.0 * x^2)
    @test PSIN.get_operation_terms(test_obj) == 10.0 * x^2 + 50.0

    @test PSIN.get_objective_expression(test_obj) == 10.0 * x^2 + 5.0 * x + 60.0
end

@testset "Investment Formulation Validation" begin
    @test_throws ArgumentError PSIN.TechnologyModel(
        PSIP.StorageTechnology{PSY.EnergyReservoirStorage},
        PSIN.BinaryInvestment,
        PSIN.CyclicalStorageDispatch,
        PSIN.BasicDispatchFeasibility,
    )
end

@testset "Operational weights check" begin
    _, op_days = test_2_zone_portfolio()
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    time_mapping = PSIN.TimeMapping(periods, op_days, Vector{Vector{DateTime}}())

    @test_logs min_level = Logging.Warn PSIN.check_operational_weights(
        time_mapping,
        [365.0, 365.0],
    )
    # Weights that include the length of the period are flagged, one warning per period.
    @test_logs(
        (:warn, r"represent 5.0 years"),
        (:warn, r"represent 5.0 years"),
        min_level = Logging.Warn,
        PSIN.check_operational_weights(time_mapping, [365.0 * 5, 365.0 * 5]),
    )
    @test_logs(
        (:warn, r"represent 0.5 years"),
        min_level = Logging.Warn,
        PSIN.check_operational_weights(time_mapping, [365.0, 182.5]),
    )
end

@testset "Time series initial timestamp check" begin
    p_5bus, op_days = test_2_zone_portfolio()
    wind = PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p_5bus, "wind")
    time_series = IS.get_time_series(
        IS.SingleTimeSeries,
        wind,
        "ops_variable_cap_factor";
        year="2030",
        rep_day=1,
    )
    @test isnothing(PSIN.check_initial_timestamp(time_series, wind, first(op_days[1]), 1))
    # A time series that starts on a different time stamp than its representative period
    # is an error.
    @test_throws ErrorException PSIN.check_initial_timestamp(
        time_series,
        wind,
        first(op_days[2]),
        2,
    )
end

@testset "Constructor" begin
    p_5bus, op_days = test_2_zone_portfolio()

    capital = DiscountedCashFlow(
        0.07, # Discount Rate
        Year(2025), # Base Year to Discount Cost (Not implemented yet)
        [
            (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
            (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
        ], # Vector of Period Duration
    )

    weights = [365, 365] # Per-year weights: each period is represented by one day
    operations = PSIN.OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}()) # Empty Feasibility

    template = InvestmentModelTemplate(
        capital,
        operations,
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(SingleRegionBalanceModel),
    )

    settings = PSIN.Settings(p_5bus)
    model = JuMP.Model(HiGHS.Optimizer)
    container = PSIN.SingleOptimizationContainer(settings, model)

    PSIN.init_optimization_container!(container, template, p_5bus)

    transport_model = PSIN.get_transport_model(template)
    PSIN.initialize_system_expressions!(container, transport_model, p_5bus)
    PSIN.initialize_demands!(container, p_5bus)

    #Define technology models
    demand_model = PSIN.TechnologyModel(
        PSIP.DemandRequirement{PSY.PowerLoad},
        PSIN.StaticLoadInvestment,
        PSIN.BasicDispatch,
        PSIN.BasicDispatchFeasibility,
    )
    vre_model = PSIN.TechnologyModel(
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSIN.ContinuousInvestment,
        PSIN.BasicDispatch,
        PSIN.BasicDispatchFeasibility,
    )
    thermal_model = PSIN.TechnologyModel(
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSIN.ContinuousInvestment,
        PSIN.BasicDispatch,
        PSIN.BasicDispatchFeasibility,
    )
    storage_type = PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
    storage_model = PSIN.TechnologyModel(
        storage_type,
        PSIN.ContinuousInvestment,
        PSIN.CyclicalStorageDispatch,
        PSIN.BasicDispatchFeasibility,
    )
    storage = PSIP.get_technology(storage_type, p_5bus, "test_storage")
    PSIP.set_duration_limits!(storage, (min=2.0, max=4.0))

    # Argument Stage

    #DemandRequirements
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSIN.ArgumentConstructStage(),
        capital,
        PSIP.DemandRequirement{PSY.PowerLoad},
        PSIN.StaticLoadInvestment,
        transport_model,
        [demand_model],
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSIN.ArgumentConstructStage(),
        operations,
        PSIP.DemandRequirement{PSY.PowerLoad},
        PSIN.BasicDispatch,
        transport_model,
        [demand_model],
    )

    # System expressions: EnergyBalance, FeasibilitySurplus, WeightedEnergyDemand, and
    # DemandExpression from initialize_demands!.
    # The demand argument stage only populates these existing containers.
    @test length(container.expressions) == 4
    @test length(container.variables) == 0

    #SupplyTechnology{RenewableDispatch}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSIN.ArgumentConstructStage(),
        capital,
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSIN.ContinuousInvestment,
        transport_model,
        [vre_model],
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSIN.ArgumentConstructStage(),
        operations,
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSIN.BasicDispatch,
        transport_model,
        [vre_model],
    )

    # + CumulativeCapacity and WeightedEnergyGeneration for the wind supply tech.
    @test length(container.expressions) == 6
    @test length(container.variables) == 2

    v = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        "ContinuousInvestment",
    )
    @test length(v) == 2

    v = PSIN.get_variable(
        container,
        PSIN.ActivePowerVariable(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        "BasicDispatch",
    )
    @test length(v["wind", :]) == length(PSIN.get_time_steps(container.time_mapping))

    e = PSIN.get_expression(
        container,
        PSIN.CumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        "ContinuousInvestment",
    )
    @test length(e["wind", :]) ==
          length(PSIN.get_investment_time_steps(container.time_mapping))

    #SupplyTechnology{ThermalStandard}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSIN.ArgumentConstructStage(),
        capital,
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSIN.ContinuousInvestment,
        transport_model,
        [thermal_model, thermal_model],
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSIN.ArgumentConstructStage(),
        operations,
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSIN.BasicDispatch,
        transport_model,
        [thermal_model, thermal_model],
    )

    # + CumulativeCapacity and WeightedEnergyGeneration for the thermal supply tech.
    @test length(container.expressions) == 8
    @test length(container.variables) == 4

    v = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        "ContinuousInvestment",
    )
    @test length(v) == 4

    v = PSIN.get_variable(
        container,
        PSIN.ActivePowerVariable(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        "BasicDispatch",
    )
    @test length(v["expensive_thermal", :]) ==
          length(PSIN.get_time_steps(container.time_mapping))
    @test length(v["cheap_thermal", :]) ==
          length(PSIN.get_time_steps(container.time_mapping))

    e = PSIN.get_expression(
        container,
        PSIN.CumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        "ContinuousInvestment",
    )
    @test length(e["expensive_thermal", :]) ==
          length(PSIN.get_investment_time_steps(container.time_mapping))
    @test length(e["cheap_thermal", :]) ==
          length(PSIN.get_investment_time_steps(container.time_mapping))

    # StorageTechnology{EnergyReservoirStorage}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["test_storage"],
        PSIN.ArgumentConstructStage(),
        capital,
        storage_type,
        PSIN.ContinuousInvestment,
        transport_model,
        [storage_model],
    )

    # Model Stage

    #DemandRequirement{PowerLoad}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSIN.ModelConstructStage(),
        capital,
        PSIP.DemandRequirement{PSY.PowerLoad},
        PSIN.StaticLoadInvestment,
        transport_model,
        [demand_model],
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSIN.ModelConstructStage(),
        operations,
        PSIP.DemandRequirement{PSY.PowerLoad},
        PSIN.BasicDispatch,
        transport_model,
        [demand_model],
    )

    @test length(container.constraints) == 0

    #SupplyTechnology{RenewableDispatch}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSIN.ModelConstructStage(),
        capital,
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSIN.ContinuousInvestment,
        transport_model,
        [vre_model],
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSIN.ModelConstructStage(),
        operations,
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSIN.BasicDispatch,
        transport_model,
        [vre_model],
    )

    @test length(container.constraints) == 2

    c = PSIN.get_constraint(
        container,
        PSIN.ActivePowerLimitsConstraint(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        "BasicDispatch",
    )
    @test length(c) == length(PSIN.get_time_steps(container.time_mapping))

    c = PSIN.get_constraint(
        container,
        PSIN.MaximumCumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        "ContinuousInvestment",
    )
    @test length(c) == length(PSIN.get_investment_time_steps(container.time_mapping))

    #SupplyTechnology{ThermalStandard}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSIN.ModelConstructStage(),
        capital,
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSIN.ContinuousInvestment,
        transport_model,
        [thermal_model, thermal_model],
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSIN.ModelConstructStage(),
        operations,
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSIN.BasicDispatch,
        transport_model,
        [thermal_model, thermal_model],
    )

    @test length(container.constraints) == 4

    c = PSIN.get_constraint(
        container,
        PSIN.MaximumCumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        "ContinuousInvestment",
    )
    @test length(c["expensive_thermal", :]) ==
          length(PSIN.get_investment_time_steps(container.time_mapping))
    @test length(c["cheap_thermal", :]) ==
          length(PSIN.get_investment_time_steps(container.time_mapping))

    # Dispatch is limited to the installed capacity that is not on a forced outage (8%)
    limit = PSIN.get_constraint(
        container,
        PSIN.ActivePowerLimitsConstraint(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        "BasicDispatch",
    )
    thermal_build = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        "ContinuousInvestment",
    )
    @test PSIP.get_outage_factors(
        PSIP.get_technology(
            PSIP.SupplyTechnology{PSY.ThermalStandard},
            p_5bus,
            "cheap_thermal",
        ),
    ) == (planned=0.0, forced=0.08)
    @test JuMP.normalized_coefficient(
        limit["cheap_thermal", 30],
        thermal_build["cheap_thermal", 2],
    ) ≈ -0.92

    # StorageTechnology{EnergyReservoirStorage}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["test_storage"],
        PSIN.ModelConstructStage(),
        capital,
        storage_type,
        PSIN.ContinuousInvestment,
        transport_model,
        [storage_model],
    )

    lower_duration = PSIN.get_constraint(
        container,
        PSIN.StorageDurationLowerBoundConstraint(),
        storage_type,
        "ContinuousInvestment",
    )
    upper_duration = PSIN.get_constraint(
        container,
        PSIN.StorageDurationUpperBoundConstraint(),
        storage_type,
        "ContinuousInvestment",
    )
    build_power = PSIN.get_variable(
        container,
        PSIN.BuildPowerCapacity(),
        storage_type,
        "ContinuousInvestment",
    )
    build_energy = PSIN.get_variable(
        container,
        PSIN.BuildEnergyCapacity(),
        storage_type,
        "ContinuousInvestment",
    )
    investment_time_steps = PSIN.get_investment_time_steps(container.time_mapping)

    @test length(lower_duration["test_storage", :]) == length(investment_time_steps)
    @test length(upper_duration["test_storage", :]) == length(investment_time_steps)

    final_time_step = last(investment_time_steps)
    lower_constraint = lower_duration["test_storage", final_time_step]
    upper_constraint = upper_duration["test_storage", final_time_step]
    @test JuMP.constraint_object(lower_constraint).set isa
          MathOptInterface.GreaterThan{Float64}
    @test JuMP.constraint_object(upper_constraint).set isa
          MathOptInterface.LessThan{Float64}
    for t in investment_time_steps
        @test JuMP.normalized_coefficient(
            lower_constraint,
            build_energy["test_storage", t],
        ) == 1.0
        @test JuMP.normalized_coefficient(
            lower_constraint,
            build_power["test_storage", t],
        ) == -2.0
        @test JuMP.normalized_coefficient(
            upper_constraint,
            build_energy["test_storage", t],
        ) == 1.0
        @test JuMP.normalized_coefficient(
            upper_constraint,
            build_power["test_storage", t],
        ) == -4.0
    end
end
