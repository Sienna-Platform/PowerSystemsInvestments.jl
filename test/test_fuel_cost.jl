const FUEL_TEST_THERMAL_TYPE = PSIP.SupplyTechnology{PSY.ThermalStandard}

function _make_fuel_cost_model(variable_cost=nothing)
    operation_cost = nothing
    if !isnothing(variable_cost)
        operation_cost = ThermalGenerationCost(;
            variable=variable_cost,
            fixed=0.0,
            start_up=0.0,
            shut_down=0.0,
        )
    end
    return thermal_test_model(BasicDispatch; operation_cost=operation_cost)
end

function _build_fuel_cost_model(variable_cost=nothing)
    m = _make_fuel_cost_model(variable_cost)
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    return m
end

function _dispatch_cost_coefficient(m::InvestmentModel, name::String, t::Int)
    container = PSIN.get_optimization_container(m)
    dispatch = PSIN.get_variable(
        container,
        PSIN.ActivePowerVariable(),
        FUEL_TEST_THERMAL_TYPE,
        "BasicDispatch",
    )
    return JuMP.coefficient(
        JuMP.objective_function(PSIN.get_jump_model(container)),
        dispatch[name, t],
    )
end

function _thermal_variable_cost(name::String)
    p_5bus, _ = test_2_zone_portfolio()
    thermal = PSIP.get_technology(FUEL_TEST_THERMAL_TYPE, p_5bus, name)
    return PSY.get_proportional_term(
        PSY.get_value_curve(PSY.get_variable(PSIP.get_operation_costs(thermal))),
    )
end

@testset "Fuel curve data" begin
    fuel_curve = FuelCurve(; value_curve=LinearCurve(9.5), fuel_cost=4.0)
    @test PSIN.get_heat_rate(fuel_curve) == 9.5
    @test PSIN.get_fuel_price(fuel_curve) == 4.0

    quadratic_fuel_curve =
        FuelCurve(; value_curve=QuadraticCurve(0.01, 9.5, 0.0), fuel_cost=4.0)
    @test_throws ErrorException PSIN.get_heat_rate(quadratic_fuel_curve)

    fuel_price_key = IS.StaticTimeSeriesKey(;
        time_series_type=IS.SingleTimeSeries,
        name="fuel_price",
        initial_timestamp=DateTime(2030),
        resolution=Hour(1),
        length=24,
        features=Dict{String, Any}(),
    )
    time_varying_fuel_curve =
        FuelCurve(; value_curve=LinearCurve(9.5), fuel_cost=fuel_price_key)
    @test_throws ErrorException PSIN.get_fuel_price(time_varying_fuel_curve)

    p_5bus, _ = test_2_zone_portfolio()
    thermal = PSIP.get_technology(FUEL_TEST_THERMAL_TYPE, p_5bus, "expensive_thermal")
    @test !PSIN.has_fuel_curve(thermal)
    PSIP.set_operation_costs!(
        thermal,
        ThermalGenerationCost(;
            variable=fuel_curve,
            fixed=0.0,
            start_up=0.0,
            shut_down=0.0,
        ),
    )
    @test PSIN.has_fuel_curve(thermal)
end

@testset "Fuel cost in the objective function" begin
    cost_per_mwh = _thermal_variable_cost("expensive_thermal")
    heat_rate = 10.0
    fuel_price = cost_per_mwh / heat_rate
    time_steps = (1, 30)

    m_cost = _build_fuel_cost_model()
    m_fuel = _build_fuel_cost_model(
        FuelCurve(; value_curve=LinearCurve(heat_rate), fuel_cost=fuel_price),
    )

    for t in time_steps
        @test _dispatch_cost_coefficient(m_fuel, "expensive_thermal", t) ≈
              _dispatch_cost_coefficient(m_cost, "expensive_thermal", t)
        @test _dispatch_cost_coefficient(m_fuel, "cheap_thermal", t) ≈
              _dispatch_cost_coefficient(m_cost, "cheap_thermal", t)
    end

    cost_container = PSIN.get_optimization_container(m_cost)
    fuel_container = PSIN.get_optimization_container(m_fuel)
    consumption_key = PSIN.ExpressionKey(
        FuelConsumptionExpression,
        FUEL_TEST_THERMAL_TYPE,
        "BasicDispatch",
    )
    fuel_cost_key = PSIN.ExpressionKey(FuelCost, FUEL_TEST_THERMAL_TYPE, "BasicDispatch")
    @test !haskey(PSIN.get_expressions(cost_container), consumption_key)
    @test !haskey(PSIN.get_expressions(cost_container), fuel_cost_key)
    consumption = PSIN.get_expressions(fuel_container)[consumption_key]
    @test axes(consumption)[1] == ["expensive_thermal"]
    @test axes(PSIN.get_expressions(fuel_container)[fuel_cost_key])[1] ==
          ["expensive_thermal"]

    dispatch = PSIN.get_variable(
        fuel_container,
        PSIN.ActivePowerVariable(),
        FUEL_TEST_THERMAL_TYPE,
        "BasicDispatch",
    )
    for t in time_steps
        @test JuMP.coefficient(
            consumption["expensive_thermal", t],
            dispatch["expensive_thermal", t],
        ) == heat_rate
    end

    @test solve!(m_cost) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test solve!(m_fuel) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test JuMP.objective_value(PSIN.get_jump_model(fuel_container)) ≈
          JuMP.objective_value(PSIN.get_jump_model(cost_container))

    dispatch_df = filter(
        r -> r.name == "expensive_thermal",
        read_variable(
            m_fuel,
            PSIN.VariableKey(ActivePowerVariable, FUEL_TEST_THERMAL_TYPE, "BasicDispatch"),
        ),
    )
    consumption_df = read_expression(m_fuel, consumption_key)
    fuel_cost_df = read_expression(m_fuel, fuel_cost_key)
    @test unique(consumption_df.name) == ["expensive_thermal"]
    @test sum(dispatch_df.value) > 0.0
    sort!(dispatch_df, :time_index)
    sort!(consumption_df, :time_index)
    sort!(fuel_cost_df, :time_index)
    @test consumption_df.value ≈ heat_rate .* dispatch_df.value
    expected_fuel_cost = [
        _dispatch_cost_coefficient(m_fuel, "expensive_thermal", r.time_index) * r.value
        for r in eachrow(dispatch_df)
    ]
    @test fuel_cost_df.value ≈ expected_fuel_cost
end

@testset "Variable OM cost of fuel and cost curves" begin
    cost_per_mwh = _thermal_variable_cost("expensive_thermal")
    heat_rate = 10.0
    fuel_price = cost_per_mwh / heat_rate
    vom = 2.0
    t = 1

    base_coefficient =
        _dispatch_cost_coefficient(_build_fuel_cost_model(), "expensive_thermal", t)
    expected_coefficient = base_coefficient * (cost_per_mwh + vom) / cost_per_mwh

    m_fuel = _build_fuel_cost_model(
        FuelCurve(;
            value_curve=LinearCurve(heat_rate),
            fuel_cost=fuel_price,
            vom_cost=LinearCurve(vom),
        ),
    )
    @test _dispatch_cost_coefficient(m_fuel, "expensive_thermal", t) ≈ expected_coefficient

    m_cost = _build_fuel_cost_model(
        CostCurve(; value_curve=LinearCurve(cost_per_mwh), vom_cost=LinearCurve(vom)),
    )
    @test _dispatch_cost_coefficient(m_cost, "expensive_thermal", t) ≈ expected_coefficient

    function cost_coefficient(m, expression_type, name)
        container = PSIN.get_optimization_container(m)
        expression = PSIN.get_expression(
            container,
            expression_type(),
            FUEL_TEST_THERMAL_TYPE,
            "BasicDispatch",
        )
        dispatch = PSIN.get_variable(
            container,
            PSIN.ActivePowerVariable(),
            FUEL_TEST_THERMAL_TYPE,
            "BasicDispatch",
        )
        return JuMP.coefficient(expression[name, t], dispatch[name, t])
    end
    @test cost_coefficient(m_fuel, FuelCost, "expensive_thermal") ≈ base_coefficient
    @test cost_coefficient(m_fuel, VariableOMCost, "expensive_thermal") ≈
          expected_coefficient - base_coefficient
    @test cost_coefficient(m_cost, VariableOMCost, "expensive_thermal") ≈
          expected_coefficient
    @test cost_coefficient(m_cost, VariableOMCost, "cheap_thermal") ≈
          _dispatch_cost_coefficient(m_cost, "cheap_thermal", t)
end

@testset "Unsupported fuel curves fail at build" begin
    m = _make_fuel_cost_model(
        FuelCurve(; value_curve=QuadraticCurve(0.01, 10.0, 0.0), fuel_cost=3.0),
    )
    build_log = build_expecting_failure(m)
    @test occursin("Variable cost curves of type", build_log)
end

@testset "Unsupported cost curves fail at build" begin
    quadratic_cost_curve = CostCurve(QuadraticCurve(0.01, 30.0, 0.0))
    @test_throws ErrorException PSIN.throw_unsupported_curve(quadratic_cost_curve)

    m = _make_fuel_cost_model(quadratic_cost_curve)
    build_log = build_expecting_failure(m)
    @test occursin("Variable cost curves of type", build_log)
end
