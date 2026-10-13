const FUEL_TEST_THERMAL_TYPE = PSIP.SupplyTechnology{PSY.ThermalStandard}

# Single region model with two thermal technologies. When a variable cost is given, it
# replaces the one of "expensive_thermal".
function _make_fuel_cost_model(variable_cost=nothing)
    p_5bus, op_days = test_2_zone_portfolio()
    thermal = PSIP.get_technology(FUEL_TEST_THERMAL_TYPE, p_5bus, "expensive_thermal")
    if !isnothing(variable_cost)
        PSIP.set_operation_costs!(
            thermal,
            ThermalGenerationCost(;
                variable=variable_cost,
                fixed=0.0,
                start_up=0.0,
                shut_down=0.0,
            ),
        )
    end

    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), periods),
        OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(SingleRegionBalanceModel, use_slacks=false),
    )
    set_technology_model!(
        template,
        ["demand1"],
        PSIP.DemandRequirement{PSY.PowerLoad},
        StaticLoadInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["cheap_thermal", "expensive_thermal"],
        FUEL_TEST_THERMAL_TYPE,
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    return InvestmentModel(
        template,
        SingleInstanceSolve,
        p_5bus;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
        store_variable_names=true,
    )
end

function _build_fuel_cost_model(variable_cost=nothing)
    m = _make_fuel_cost_model(variable_cost)
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    return m
end

# Objective function coefficient of the dispatch of a thermal technology in a time step.
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

    # Only linear fuel curves are supported.
    quadratic_fuel_curve =
        FuelCurve(; value_curve=QuadraticCurve(0.01, 9.5, 0.0), fuel_cost=4.0)
    @test_throws ErrorException PSIN.get_heat_rate(quadratic_fuel_curve)

    # Fuel prices given as a time series are not supported.
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

    # A heat rate and a fuel price cost the same as the equivalent cost per MWh.
    for t in time_steps
        @test _dispatch_cost_coefficient(m_fuel, "expensive_thermal", t) ≈
              _dispatch_cost_coefficient(m_cost, "expensive_thermal", t)
        @test _dispatch_cost_coefficient(m_fuel, "cheap_thermal", t) ≈
              _dispatch_cost_coefficient(m_cost, "cheap_thermal", t)
    end

    # Fuel expressions only exist for the technologies with a fuel curve.
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

    # Results: fuel consumption is the heat rate times the dispatch, and the fuel cost is
    # the objective function cost of that dispatch.
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
end

@testset "Unsupported fuel curves fail at build" begin
    m = _make_fuel_cost_model(
        FuelCurve(; value_curve=QuadraticCurve(0.01, 10.0, 0.0), fuel_cost=3.0),
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.FAILED
end
