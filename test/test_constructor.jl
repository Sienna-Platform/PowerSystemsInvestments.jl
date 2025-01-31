@testset "Objective Function" begin
    test_obj = PSINV.ObjectiveFunction()
    @test PSINV.get_capital_terms(test_obj) == zero(AffExpr)
    @test PSINV.get_operation_terms(test_obj) == zero(AffExpr)
    @test PSINV.get_objective_expression(test_obj) == zero(AffExpr)
    @test PSINV.get_sense(test_obj) == JuMP.MOI.MIN_SENSE

    test_obj = PSINV.ObjectiveFunction()
    PSINV.add_to_capital_terms(test_obj, 10.0)
    m = JuMP.Model()
    x = JuMP.@variable(m)
    PSINV.add_to_capital_terms(test_obj, 5.0 * x)
    @test PSINV.get_capital_terms(test_obj) == 5.0 * x + 10.0

    PSINV.add_to_operation_terms(test_obj, 50.0)
    y = JuMP.@variable(m)
    PSINV.add_to_operation_terms(test_obj, 10.0 * x^2)
    @test PSINV.get_operation_terms(test_obj) == 10.0 * x^2 + 50.0

    @test PSINV.get_objective_expression(test_obj) == 10.0 * x^2 + 5.0 * x + 60.0
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

    settings = PSINV.Settings(p_5bus)
    model = JuMP.Model(HiGHS.Optimizer)
    container = PSINV.SingleOptimizationContainer(settings, model)

    PSINV.init_optimization_container!(container, template, p_5bus)

    transport_model = PSINV.get_transport_model(template)
    PSINV.initialize_system_expressions!(container, transport_model, p_5bus)

    #Define technology models
    demand_model = PSINV.TechnologyModel(
        PSIP.DemandRequirement{PSY.PowerLoad},
        PSINV.StaticLoadInvestment,
        PSINV.BasicDispatch,
        PSINV.BasicDispatchFeasibility,
    )
    vre_model = PSINV.TechnologyModel(
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSINV.ContinuousInvestment,
        PSINV.BasicDispatch,
        PSINV.BasicDispatchFeasibility,
    )
    thermal_model = PSINV.TechnologyModel(
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSINV.ContinuousInvestment,
        PSINV.BasicDispatch,
        PSINV.BasicDispatchFeasibility,
    )

    # Argument Stage

    #DemandRequirements
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSINV.ArgumentConstructStage(),
        capital,
        demand_model,
        transport_model,
    )
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSINV.ArgumentConstructStage(),
        operations,
        demand_model,
        transport_model,
    )

    @test length(container.expressions) == 2
    @test length(container.variables) == 0

    #SupplyTechnology{RenewableDispatch}
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSINV.ArgumentConstructStage(),
        capital,
        vre_model,
        transport_model,
    )
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSINV.ArgumentConstructStage(),
        operations,
        vre_model,
        transport_model,
    )

    @test length(container.expressions) == 3
    @test length(container.variables) == 2

    v = PSINV.get_variable(
        container,
        PSINV.BuildCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSINV.get_investment_formulation(vre_model)),
    )
    @test length(v) == 2

    v = PSINV.get_variable(
        container,
        PSINV.ActivePowerVariable(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSINV.get_investment_formulation(vre_model)),
    )
    @test length(v["wind", :]) == length(PSINV.get_time_steps(container.time_mapping))

    e = PSINV.get_expression(
        container,
        PSINV.CumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSINV.get_investment_formulation(vre_model)),
    )
    @test length(e["wind", :]) ==
          length(PSINV.get_investment_time_steps(container.time_mapping))

    #SupplyTechnology{ThermalStandard}
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSINV.ArgumentConstructStage(),
        capital,
        thermal_model,
        transport_model,
    )
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSINV.ArgumentConstructStage(),
        operations,
        thermal_model,
        transport_model,
    )

    @test length(container.expressions) == 4
    @test length(container.variables) == 4

    v = PSINV.get_variable(
        container,
        PSINV.BuildCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        string(PSINV.get_investment_formulation(thermal_model)),
    )
    @test length(v) == 4

    v = PSINV.get_variable(
        container,
        PSINV.ActivePowerVariable(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        string(PSINV.get_investment_formulation(thermal_model)),
    )
    @test length(v["expensive_thermal", :]) ==
          length(PSINV.get_time_steps(container.time_mapping))
    @test length(v["cheap_thermal", :]) ==
          length(PSINV.get_time_steps(container.time_mapping))

    e = PSINV.get_expression(
        container,
        PSINV.CumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        string(PSINV.get_investment_formulation(thermal_model)),
    )
    @test length(e["expensive_thermal", :]) ==
          length(PSINV.get_investment_time_steps(container.time_mapping))
    @test length(e["cheap_thermal", :]) ==
          length(PSINV.get_investment_time_steps(container.time_mapping))

    # Model Stage

    #DemandRequirement{PowerLoad}
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSINV.ModelConstructStage(),
        capital,
        demand_model,
        transport_model,
    )
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["demand1"],
        PSINV.ModelConstructStage(),
        operations,
        demand_model,
        transport_model,
    )

    @test length(container.constraints) == 0

    #SupplyTechnology{RenewableDispatch}
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSINV.ModelConstructStage(),
        capital,
        vre_model,
        transport_model,
    )
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["wind"],
        PSINV.ModelConstructStage(),
        operations,
        vre_model,
        transport_model,
    )

    @test length(container.constraints) == 2

    c = PSINV.get_constraint(
        container,
        PSINV.ActivePowerLimitsConstraint(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSINV.get_investment_formulation(vre_model)),
    )
    @test length(c) == length(PSINV.get_time_steps(container.time_mapping))

    c = PSINV.get_constraint(
        container,
        PSINV.MaximumCumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        string(PSINV.get_investment_formulation(vre_model)),
    )
    @test length(c) == length(PSINV.get_investment_time_steps(container.time_mapping))

    #SupplyTechnology{ThermalStandard}
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSINV.ModelConstructStage(),
        capital,
        thermal_model,
        transport_model,
    )
    PSINV.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal", "expensive_thermal"],
        PSINV.ModelConstructStage(),
        operations,
        thermal_model,
        transport_model,
    )

    @test length(container.constraints) == 4

    c = PSINV.get_constraint(
        container,
        PSINV.MaximumCumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        string(PSINV.get_investment_formulation(thermal_model)),
    )
    @test length(c["expensive_thermal", :]) ==
          length(PSINV.get_investment_time_steps(container.time_mapping))
    @test length(c["cheap_thermal", :]) ==
          length(PSINV.get_investment_time_steps(container.time_mapping))

    #passing same technology name with different model to constructor
    # TODO: This tests is not failing but should fail!!!!!
    #=
    unit_thermal_model = PSINV.TechnologyModel(
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSINV.IntegerInvestment,
        PSINV.BasicDispatch,
        PSINV.BasicDispatchFeasibility;
    )

    @test_throws ArgumentError PSINV.construct_technologies!(
        container,
        p_5bus,
        ["cheap_thermal"],
        PSINV.ArgumentConstructStage(),
        capital,
        unit_thermal_model,
        transport_model,
    )
    =#
end
