@testset "Thermal commitment constraints" begin
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    p_5bus, op_days = test_2_zone_portfolio()
    name = "expensive_thermal"
    thermal = PSIP.get_technology(thermal_type, p_5bus, name)
    PSIP.set_time_limits!(thermal, (up=3.0, down=2.0))
    PSIP.set_ramp_limits!(thermal, (up=0.3, down=0.4))
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
    @test coefficient(min_down[name, 1], build[name, 1]) == -1.0

    # Ramp limits apply to the capacity that stays committed.
    ramp_up = constraint(PSIN.RampRateConstraint(), "$(meta)_up")
    ramp_down = constraint(PSIN.RampRateConstraint(), "$(meta)_dn")
    @test coefficient(ramp_up[name, 1], dispatch[name, 1]) == 1.0
    @test coefficient(ramp_up[name, 1], dispatch[name, 24]) == -1.0
    @test coefficient(ramp_up[name, 1], committed[name, 1]) ≈ -0.3
    @test coefficient(ramp_up[name, 1], start_up[name, 1]) ≈ 0.3 - 1.0
    @test coefficient(ramp_down[name, 1], dispatch[name, 24]) == 1.0
    @test coefficient(ramp_down[name, 1], committed[name, 1]) ≈ -0.4
    @test coefficient(ramp_down[name, 1], start_up[name, 1]) ≈ 0.4
    @test coefficient(ramp_down[name, 1], shut_down[name, 1]) == -1.0

    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

    # The solution respects the commitment and ramp limits.
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
    start_up_values = values(PSIN.StartUpCapacityVariable)
    tol = 1e-4
    @test all(dispatch_values .<= committed_values .+ tol)
    for t in 2:24
        @test dispatch_values[t] - dispatch_values[t - 1] <=
              0.3 * (committed_values[t] - start_up_values[t]) + start_up_values[t] + tol
    end
end
