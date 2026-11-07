@testset "Thermal commitment constraints" begin
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    p_5bus, op_days = test_2_zone_portfolio()
    name = "expensive_thermal"
    thermal = PSIP.get_technology(thermal_type, p_5bus, name)
    PSIP.set_time_limits!(thermal, (up=3.0, down=2.0))
    PSIP.set_ramp_limits!(thermal, (up=0.3, down=0.4))
    PSIP.set_min_generation_fraction!(thermal, 0.35)
    forced_outage = PSIP.get_outage_factors(thermal).forced
    @test forced_outage > 0.0

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
        ["cheap_thermal", name],
        thermal_type,
        ContinuousInvestment,
        ContinuousThermalCommitment,
        BasicDispatchFeasibility,
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

    container = PSIN.get_optimization_container(m)
    meta = string(ContinuousThermalCommitment)
    variable(variable_type) =
        PSIN.get_variable(container, variable_type, thermal_type, meta)
    constraint(constraint_type, constraint_meta=meta) =
        PSIN.get_constraint(container, constraint_type, thermal_type, constraint_meta)
    dispatch = variable(PSIN.ActivePowerVariable())
    committed = variable(PSIN.CommittedCapacityVariable())
    start_up = variable(PSIN.StartUpCapacityVariable())
    shut_down = variable(PSIN.ShutDownCapacityVariable())
    build = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        thermal_type,
        "ContinuousInvestment",
    )
    coefficient = JuMP.normalized_coefficient

    # Dispatch is limited by the committed capacity, and the committed capacity by the
    # installed capacity that is not on outage.
    dispatch_limit = constraint(PSIN.ActivePowerLimitsConstraint())
    @test coefficient(dispatch_limit[name, 5], dispatch[name, 5]) == 1.0
    @test coefficient(dispatch_limit[name, 5], committed[name, 5]) == -1.0
    # Committed capacity produces at least its minimum output.
    min_dispatch_limit = constraint(PSIN.ActivePowerLimitsConstraint(), "$(meta)_lb")
    @test coefficient(min_dispatch_limit[name, 5], dispatch[name, 5]) == 1.0
    @test coefficient(min_dispatch_limit[name, 5], committed[name, 5]) ≈ -0.35
    # A technology without a minimum output only has to be non-negative.
    @test coefficient(
        min_dispatch_limit["cheap_thermal", 5],
        committed["cheap_thermal", 5],
    ) == 0.0
    committed_limit = constraint(PSIN.CommittedCapacityLimitConstraint())
    @test coefficient(committed_limit[name, 5], build[name, 1]) ≈ -(1.0 - forced_outage)
    # Time step 30 is in the second investment period.
    @test coefficient(committed_limit[name, 30], build[name, 2]) ≈ -(1.0 - forced_outage)

    # Committed capacity follows the capacity started up and shut down. The time step
    # before the first one of a representative day is the last one of that day.
    tracking = constraint(PSIN.CommittedCapacityTrackingConstraint())
    @test coefficient(tracking[name, 5], committed[name, 4]) == -1.0
    @test coefficient(tracking[name, 5], start_up[name, 5]) == -1.0
    @test coefficient(tracking[name, 5], shut_down[name, 5]) == 1.0
    @test coefficient(tracking[name, 1], committed[name, 24]) == -1.0
    @test coefficient(tracking[name, 25], committed[name, 48]) == -1.0
    @test coefficient(tracking[name, 25], committed[name, 24]) == 0.0

    # A minimum up time of 3 hours covers the start ups of the time step and the two
    # before it.
    min_up = constraint(PSIN.MinimumUpTimeConstraint())
    for t in (10, 9, 8)
        @test coefficient(min_up[name, 10], start_up[name, t]) == -1.0
    end
    @test coefficient(min_up[name, 10], start_up[name, 7]) == 0.0
    for t in (1, 24, 23)
        @test coefficient(min_up[name, 1], start_up[name, t]) == -1.0
    end
    @test coefficient(min_up[name, 1], start_up[name, 22]) == 0.0

    # A minimum down time of 2 hours covers the shut downs of the time step and the one
    # before it.
    min_down = constraint(PSIN.MinimumDownTimeConstraint())
    @test coefficient(min_down[name, 1], shut_down[name, 1]) == 1.0
    @test coefficient(min_down[name, 1], shut_down[name, 24]) == 1.0
    @test coefficient(min_down[name, 1], shut_down[name, 23]) == 0.0
    # The capacity that can be committed is the installed capacity that is not on outage.
    @test coefficient(min_down[name, 1], build[name, 1]) ≈ -(1.0 - forced_outage)

    # The other thermal technology keeps the default minimum times of one hour.
    @test coefficient(min_up["cheap_thermal", 10], start_up["cheap_thermal", 10]) == -1.0
    @test coefficient(min_up["cheap_thermal", 10], start_up["cheap_thermal", 9]) == 0.0

    # Ramp limits: 0.3 up and 0.4 down per hour, with a minimum output of 0.35.
    # Up:   P[t] - P[t-1] <= 0.3 (u - v) + max(0.35, 0.3) v - 0.35 w
    # Down: P[t-1] - P[t] <= 0.4 (u - v) + max(0.35, 0.4) w - 0.35 v
    ramp_up = constraint(PSIN.RampRateConstraint(), "$(meta)_up")
    ramp_down = constraint(PSIN.RampRateConstraint(), "$(meta)_dn")
    @test coefficient(ramp_up[name, 1], dispatch[name, 1]) == 1.0
    @test coefficient(ramp_up[name, 1], dispatch[name, 24]) == -1.0
    @test coefficient(ramp_up[name, 1], committed[name, 1]) ≈ -0.3
    @test coefficient(ramp_up[name, 1], start_up[name, 1]) ≈ 0.3 - 0.35
    @test coefficient(ramp_up[name, 1], shut_down[name, 1]) ≈ 0.35
    @test coefficient(ramp_down[name, 1], dispatch[name, 24]) == 1.0
    @test coefficient(ramp_down[name, 1], dispatch[name, 1]) == -1.0
    @test coefficient(ramp_down[name, 1], committed[name, 1]) ≈ -0.4
    @test coefficient(ramp_down[name, 1], start_up[name, 1]) ≈ 0.4 + 0.35
    @test coefficient(ramp_down[name, 1], shut_down[name, 1]) ≈ -0.4

    # Without a minimum output, the output can change by the ramp limit times the committed
    # capacity, whether or not capacity starts up.
    @test coefficient(ramp_up["cheap_thermal", 1], committed["cheap_thermal", 1]) ≈ -1.0
    @test coefficient(ramp_up["cheap_thermal", 1], start_up["cheap_thermal", 1]) == 0.0
    @test coefficient(ramp_up["cheap_thermal", 1], shut_down["cheap_thermal", 1]) == 0.0

    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

    # The solution respects the commitment limits.
    values(variable_type) =
        sort!(
            filter(
                r -> r.name == name,
                read_variable(m, PSIN.VariableKey(variable_type, thermal_type, meta)),
            ),
            :time_index,
        ).value
    dispatch_values = values(PSIN.ActivePowerVariable)
    committed_values = values(PSIN.CommittedCapacityVariable)
    tol = 1e-4
    @test all(dispatch_values .<= committed_values .+ tol)
    @test all(dispatch_values .>= 0.35 .* committed_values .- tol)
end

# Objective and solution of a single region model where both thermal technologies use the
# commitment formulation with the given ramp limits and start-up cost ($/MW)
function _ramp_test_solution(ramp_limits, start_up_cost)
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    p_5bus, op_days = test_2_zone_portfolio()
    for name in ("cheap_thermal", "expensive_thermal")
        thermal = PSIP.get_technology(thermal_type, p_5bus, name)
        PSIP.set_ramp_limits!(thermal, ramp_limits)
        PSIP.set_min_generation_fraction!(thermal, 0.35)
        cost = PSIP.get_operation_costs(thermal)
        PSIP.set_operation_costs!(
            thermal,
            ThermalGenerationCost(;
                variable=PSY.get_variable(cost),
                fixed=PSY.get_fixed(cost),
                start_up=start_up_cost,
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
        RepresentativePeriods(Vector{Vector{DateTime}}()),
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
        thermal_type,
        ContinuousInvestment,
        ContinuousThermalCommitment,
        BasicDispatchFeasibility,
    )
    m = InvestmentModel(
        template,
        SingleInstanceSolve,
        p_5bus;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    container = PSIN.get_optimization_container(m)
    meta = string(ContinuousThermalCommitment)
    values(variable_type) =
        JuMP.value.(PSIN.get_variable(container, variable_type, thermal_type, meta).data)
    return (
        objective=JuMP.objective_value(PSIN.get_jump_model(container)),
        time_mapping=PSIN.get_time_mapping(container),
        dispatch=values(PSIN.ActivePowerVariable()),
        committed=values(PSIN.CommittedCapacityVariable()),
        start_up=values(PSIN.StartUpCapacityVariable()),
        shut_down=values(PSIN.ShutDownCapacityVariable()),
    )
end

@testset "Thermal ramp limits bind" begin
    # Ramping is free with limits of 1.0, so limits of 0.05 must raise the cost
    for (ramp_limits, loose_limits) in (
        ((up=0.05, down=1.0), (up=1.0, down=1.0)),
        ((up=1.0, down=0.05), (up=1.0, down=1.0)),
    )
        solution = _ramp_test_solution(ramp_limits, 1000.0)
        @test solution.objective > _ramp_test_solution(loose_limits, 1000.0).objective
        # The ramps of every time step, including from the last time step of each
        # representative day to its first, are within the limits
        largest_excess = -Inf
        for (op_ix, steps) in ((1, 1:24), (2, 25:48)), t in steps
            previous = PSIN.get_previous_time_step(solution.time_mapping, op_ix, t)
            for row in axes(solution.dispatch, 1)
                P(τ) = solution.dispatch[row, τ]
                u, v, w = solution.committed[row, t],
                solution.start_up[row, t],
                solution.shut_down[row, t]
                up_excess =
                    P(t) - P(previous) -
                    (ramp_limits.up * (u - v) + max(0.35, ramp_limits.up) * v - 0.35 * w)
                down_excess =
                    P(previous) - P(t) - (
                        ramp_limits.down * (u - v) + max(0.35, ramp_limits.down) * w -
                        0.35 * v
                    )
                largest_excess = max(largest_excess, up_excess, down_excess)
            end
        end
        # The tight limit binds somewhere and is never exceeded
        @test largest_excess ≈ 0.0 atol = 1e-4
    end
end

# Single region model where the thermal technologies use the commitment formulation and
# "expensive_thermal" has the given operation cost.
function _commitment_cost_test_model(operation_cost)
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    p_5bus, op_days = test_2_zone_portfolio()
    thermal = PSIP.get_technology(thermal_type, p_5bus, "expensive_thermal")
    PSIP.set_operation_costs!(thermal, operation_cost)
    PSIP.set_time_limits!(thermal, (up=3.0, down=2.0))
    PSIP.set_min_generation_fraction!(thermal, 0.35)

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
        thermal_type,
        ContinuousInvestment,
        ContinuousThermalCommitment,
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

@testset "Thermal commitment start-up, shut-down and no-load costs" begin
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    name = "expensive_thermal"
    heat_rate = 10.0
    no_load_fuel = 4.0
    fuel_price = 3.0
    start_up_fuel = 2.0
    start_up_cost = 50.0
    shut_down_cost = 20.0
    m = _commitment_cost_test_model(
        ThermalGenerationCost(;
            variable=FuelCurve(;
                value_curve=LinearCurve(heat_rate, no_load_fuel),
                fuel_cost=fuel_price,
                startup_fuel_offtake=LinearCurve(start_up_fuel),
            ),
            fixed=0.0,
            start_up=start_up_cost,
            shut_down=shut_down_cost,
        ),
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT

    container = PSIN.get_optimization_container(m)
    meta = string(ContinuousThermalCommitment)
    variable(variable_type) =
        PSIN.get_variable(container, variable_type, thermal_type, meta)
    dispatch = variable(PSIN.ActivePowerVariable())
    committed = variable(PSIN.CommittedCapacityVariable())
    start_up = variable(PSIN.StartUpCapacityVariable())
    shut_down = variable(PSIN.ShutDownCapacityVariable())
    objective = JuMP.objective_function(PSIN.get_jump_model(container))
    cost(v) = JuMP.coefficient(objective, v)

    # Time steps are one hour long, so the weighting and discounting of a time step is the
    # same for every cost. It is recovered from the cost of dispatch, which is the heat rate
    # times the fuel price per MWh.
    for t in (1, 30)
        weighting = cost(dispatch[name, t]) / (heat_rate * fuel_price)
        @test weighting > 0.0
        # No-load fuel of the committed capacity
        @test cost(committed[name, t]) ≈ no_load_fuel * fuel_price * weighting
        # Start-up cost plus the cost of the start-up fuel
        @test cost(start_up[name, t]) ≈
              (start_up_cost + start_up_fuel * fuel_price) * weighting
        @test cost(shut_down[name, t]) ≈ shut_down_cost * weighting
        # A technology with a cost curve and no start-up or shut-down cost
        @test cost(committed["cheap_thermal", t]) == 0.0
        @test cost(start_up["cheap_thermal", t]) == 0.0
        @test cost(shut_down["cheap_thermal", t]) == 0.0
    end

    # Fuel consumption includes the no-load and the start-up fuel.
    consumption =
        PSIN.get_expression(container, FuelConsumptionExpression(), thermal_type, meta)
    @test axes(consumption)[1] == [name]
    @test JuMP.coefficient(consumption[name, 5], dispatch[name, 5]) == heat_rate
    @test JuMP.coefficient(consumption[name, 5], committed[name, 5]) == no_load_fuel
    @test JuMP.coefficient(consumption[name, 5], start_up[name, 5]) == start_up_fuel
    @test JuMP.coefficient(consumption[name, 5], shut_down[name, 5]) == 0.0

    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

    # Results: the start-up and shut-down costs are the objective function costs of the
    # capacity started up and shut down, without the cost of the start-up fuel.
    function result_values(df)
        return sort!(filter(r -> r.name == name, df), :time_index).value
    end
    variable_values(variable_type) =
        result_values(read_variable(m, PSIN.VariableKey(variable_type, thermal_type, meta)))
    expression_values(expression_type) = result_values(
        read_expression(m, PSIN.ExpressionKey(expression_type, thermal_type, meta)),
    )
    weighting = [cost(dispatch[name, t]) / (heat_rate * fuel_price) for t in 1:48]
    start_up_values = variable_values(PSIN.StartUpCapacityVariable)
    shut_down_values = variable_values(PSIN.ShutDownCapacityVariable)
    committed_values = variable_values(PSIN.CommittedCapacityVariable)
    dispatch_values = variable_values(PSIN.ActivePowerVariable)
    @test expression_values(StartUpCost) ≈ start_up_cost .* weighting .* start_up_values
    @test expression_values(ShutDownCost) ≈ shut_down_cost .* weighting .* shut_down_values
    @test expression_values(FuelConsumptionExpression) ≈
          heat_rate .* dispatch_values .+ no_load_fuel .* committed_values .+
          start_up_fuel .* start_up_values
    @test expression_values(FuelCost) ≈
          fuel_price .* weighting .* expression_values(FuelConsumptionExpression)
end

@testset "Thermal commitment no-load cost of a cost curve" begin
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    name = "expensive_thermal"
    cost_per_mwh = 30.0
    no_load_cost = 4.0
    m = _commitment_cost_test_model(
        ThermalGenerationCost(;
            variable=CostCurve(LinearCurve(cost_per_mwh, no_load_cost)),
            fixed=0.0,
            start_up=0.0,
            shut_down=0.0,
        ),
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT

    container = PSIN.get_optimization_container(m)
    meta = string(ContinuousThermalCommitment)
    variable(variable_type) =
        PSIN.get_variable(container, variable_type, thermal_type, meta)
    objective = JuMP.objective_function(PSIN.get_jump_model(container))
    for t in (1, 30)
        # The constant term is a cost per hour and MW committed, weighted like the cost of
        # dispatch.
        dispatch_cost =
            JuMP.coefficient(objective, variable(PSIN.ActivePowerVariable())[name, t])
        @test JuMP.coefficient(
            objective,
            variable(PSIN.CommittedCapacityVariable())[name, t],
        ) ≈ dispatch_cost * no_load_cost / cost_per_mwh
        @test JuMP.coefficient(
            objective,
            variable(PSIN.StartUpCapacityVariable())[name, t],
        ) == 0.0
    end
    # A cost curve has no fuel.
    @test !haskey(
        PSIN.get_expressions(container),
        PSIN.ExpressionKey(FuelConsumptionExpression, thermal_type, meta),
    )
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Start-up costs by stages are not supported" begin
    m = _commitment_cost_test_model(
        ThermalGenerationCost(;
            variable=CostCurve(LinearCurve(30.0)),
            fixed=0.0,
            start_up=(hot=10.0, warm=20.0, cold=30.0),
            shut_down=0.0,
        ),
    )
    @test build!(
        m;
        output_dir=mktempdir(; cleanup=true),
        console_level=Logging.AboveMaxLevel,
    ) == IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.FAILED
end
