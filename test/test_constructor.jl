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

@testset "Constructor" begin
    p_5bus, op_days = test_data()

    capital = DiscountedCashFlow(
        0.07, # Discount Rate
        Year(2025), # Base Year to Discount Cost (Not implemented yet)
        [
            (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
            (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
        ], # Vector of Period Duration
    )

    weights = [365 * 5, 365 * 5] # Each day is weighted for a year and then 5 year period length
    operations = PSIN.OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}()) # Empty Feasibility

    template = InvestmentModelTemplate(
        capital,
        operations,
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(SingleRegionBalanceModel, use_slacks=false),
    )

    settings = PSIN.Settings(p_5bus)
    model = JuMP.Model(HiGHS.Optimizer)
    container = PSIN.SingleOptimizationContainer(settings, model)

    PSIN.init_optimization_container!(container, template, p_5bus)

    transport_model = PSIN.get_transport_model(template)
    PSIN.initialize_system_expressions!(container, transport_model, p_5bus)

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

    # Argument Stage

    #DemandRequirements
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSIN.ArgumentConstructStage(),
        capital,
        demand_model,
        transport_model,
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSIN.ArgumentConstructStage(),
        operations,
        demand_model,
        transport_model,
    )

    @test length(container.expressions) == 2
    @test length(container.variables) == 0

    #SupplyTechnology{RenewableDispatch}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSIN.ArgumentConstructStage(),
        capital,
        vre_model,
        transport_model,
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSIN.ArgumentConstructStage(),
        operations,
        vre_model,
        transport_model,
    )

    @test length(container.expressions) == 3
    @test length(container.variables) == 2

    v = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSIN.get_investment_formulation(vre_model)),
    )
    @test length(v) == 2

    v = PSIN.get_variable(
        container,
        PSIN.ActivePowerVariable(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSIN.get_investment_formulation(vre_model)),
    )
    @test length(v["wind", :]) == length(PSIN.get_time_steps(container.time_mapping))

    e = PSIN.get_expression(
        container,
        PSIN.CumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSIN.get_investment_formulation(vre_model)),
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
        thermal_model,
        transport_model,
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSIN.ArgumentConstructStage(),
        operations,
        thermal_model,
        transport_model,
    )

    @test length(container.expressions) == 4
    @test length(container.variables) == 4

    v = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        string(PSIN.get_investment_formulation(thermal_model)),
    )
    @test length(v) == 4

    v = PSIN.get_variable(
        container,
        PSIN.ActivePowerVariable(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        string(PSIN.get_investment_formulation(thermal_model)),
    )
    @test length(v["expensive_thermal", :]) ==
          length(PSIN.get_time_steps(container.time_mapping))
    @test length(v["cheap_thermal", :]) ==
          length(PSIN.get_time_steps(container.time_mapping))

    e = PSIN.get_expression(
        container,
        PSIN.CumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        string(PSIN.get_investment_formulation(thermal_model)),
    )
    @test length(e["expensive_thermal", :]) ==
          length(PSIN.get_investment_time_steps(container.time_mapping))
    @test length(e["cheap_thermal", :]) ==
          length(PSIN.get_investment_time_steps(container.time_mapping))

    # Model Stage

    #DemandRequirement{PowerLoad}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSIN.ModelConstructStage(),
        capital,
        demand_model,
        transport_model,
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSIN.ModelConstructStage(),
        operations,
        demand_model,
        transport_model,
    )

    @test length(container.constraints) == 0

    #SupplyTechnology{RenewableDispatch}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSIN.ModelConstructStage(),
        capital,
        vre_model,
        transport_model,
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSIN.ModelConstructStage(),
        operations,
        vre_model,
        transport_model,
    )

    @test length(container.constraints) == 2

    c = PSIN.get_constraint(
        container,
        PSIN.ActivePowerLimitsConstraint(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSIN.get_investment_formulation(vre_model)),
    )
    @test length(c) == length(PSIN.get_time_steps(container.time_mapping))

    c = PSIN.get_constraint(
        container,
        PSIN.MaximumCumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSIN.get_investment_formulation(vre_model)),
    )
    @test length(c) == length(PSIN.get_investment_time_steps(container.time_mapping))

    #SupplyTechnology{ThermalStandard}
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSIN.ModelConstructStage(),
        capital,
        thermal_model,
        transport_model,
    )
    PSIN.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSIN.ModelConstructStage(),
        operations,
        thermal_model,
        transport_model,
    )

    @test length(container.constraints) == 4

    c = PSIN.get_constraint(
        container,
        PSIN.MaximumCumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        string(PSIN.get_investment_formulation(thermal_model)),
    )
    @test length(c["expensive_thermal", :]) ==
          length(PSIN.get_investment_time_steps(container.time_mapping))
    @test length(c["cheap_thermal", :]) ==
          length(PSIN.get_investment_time_steps(container.time_mapping))

end
