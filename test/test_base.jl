#include("test_utils.jl/test_data.jl")

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
    p_5bus = test_data()

    settings = PSINV.Settings(p_5bus)
    model = JuMP.Model(HiGHS.Optimizer)
    container = PSINV.SingleOptimizationContainer(settings, model)
    PSINV.set_time_steps!(container, 1:48)
    PSINV.set_time_steps_investments!(container, 1:2)

    #Define technology models
    demand_model = PSINV.TechnologyModel(
        PSIP.DemandRequirement{PSY.PowerLoad},
        PSINV.ContinuousInvestment,
        PSINV.BasicDispatch,
    )
    vre_model = PSINV.TechnologyModel(
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSINV.ContinuousInvestment,
        PSINV.BasicDispatch,
    )
    thermal_model = PSINV.TechnologyModel(
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSINV.ContinuousInvestment,
        PSINV.BasicDispatch,
    )

    # Argument Stage

    #DemandRequirements
    PSINV.construct_device!(container, p_5bus, PSINV.ArgumentConstructStage(), demand_model)

    @test length(container.expressions) == 2
    @test length(container.variables) == 0

    e = PSINV.get_expression(
        container,
        PSINV.SupplyTotal(),
        PSIP.DemandRequirement{PSY.PowerLoad},
    )
    @test length(e) == length(PSIN.get_time_steps(container))

    e = PSINV.get_expression(
        container,
        PSINV.DemandTotal(),
        PSIP.DemandRequirement{PSY.PowerLoad},
    )
    @test length(e) == length(PSIN.get_time_steps(container))

    #SupplyTechnology{RenewableDispatch}
    PSINV.construct_device!(container, p_5bus, PSINV.ArgumentConstructStage(), vre_model)

    @test length(container.expressions) == 3
    @test length(container.variables) == 2

    v = PSINV.get_variable(
        container,
        PSINV.BuildCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
    )
    @test length(v) == 2

    v = PSINV.get_variable(
        container,
        PSINV.ActivePowerVariable(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
    )
    @test length(v["wind", :]) == length(PSIN.get_time_steps(container))

    e = PSINV.get_expression(
        container,
        PSINV.CumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
    )
    @test length(e["wind", :]) == length(PSIN.get_time_steps_investments(container))

    #SupplyTechnology{ThermalStandard}
    PSINV.construct_device!(
        container,
        p_5bus,
        PSINV.ArgumentConstructStage(),
        thermal_model,
    )

    @test length(container.expressions) == 4
    @test length(container.variables) == 4

    v = PSINV.get_variable(
        container,
        PSINV.BuildCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
    )
    @test length(v) == 4

    v = PSINV.get_variable(
        container,
        PSINV.ActivePowerVariable(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
    )
    @test length(v["expensive_thermal", :]) == length(PSIN.get_time_steps(container))
    @test length(v["cheap_thermal", :]) == length(PSIN.get_time_steps(container))

    e = PSINV.get_expression(
        container,
        PSINV.CumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
    )
    @test length(e["expensive_thermal", :]) ==
          length(PSIN.get_time_steps_investments(container))
    @test length(e["cheap_thermal", :]) ==
          length(PSIN.get_time_steps_investments(container))

    # Model Stage

    #DemandRequirement{PowerLoad}
    PSINV.construct_device!(container, p_5bus, PSINV.ModelConstructStage(), demand_model)

    @test length(container.constraints) == 1

    c = PSINV.get_constraint(
        container,
        PSINV.SupplyDemandBalance(),
        PSIP.DemandRequirement{PSY.PowerLoad},
    )
    @test length(c) == length(PSIN.get_time_steps(container))

    #SupplyTechnology{RenewableDispatch}
    PSINV.construct_device!(container, p_5bus, PSINV.ModelConstructStage(), vre_model)

    @test length(container.constraints) == 3

    c = PSINV.get_constraint(
        container,
        PSINV.ActivePowerLimitsConstraint(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
    )
    @test length(c) == length(PSIN.get_time_steps(container))

    c = PSINV.get_constraint(
        container,
        PSINV.MaximumCumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
    )
    @test length(c) == length(PSIN.get_time_steps_investments(container))

    #SupplyTechnology{RenewableDispatch}
    PSINV.construct_device!(container, p_5bus, PSINV.ModelConstructStage(), thermal_model)

    @test length(container.constraints) == 5

    c = PSINV.get_constraint(
        container,
        PSINV.ActivePowerLimitsConstraint(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
    )
    @test length(c["expensive_thermal", :]) == length(PSIN.get_time_steps(container))
    @test length(c["cheaper_thermal", :]) == length(PSIN.get_time_steps(container))

    c = PSINV.get_constraint(
        container,
        PSINV.MaximumCumulativeCapacity(),
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
    )
    @test length(c["expensive_thermal", :]) ==
          length(PSIN.get_time_steps_investments(container))
    @test length(c["cheap_thermal", :]) ==
          length(PSIN.get_time_steps_investments(container))
end
