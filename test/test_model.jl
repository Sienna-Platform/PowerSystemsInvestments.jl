@testset "Build and solve 2 Zone Portfolio" begin
    p_5bus, op_days = test_2_zone_portfolio()
    # 2 representative days (24-hours for 5 years each)
    weights = [365 * 5, 365 * 5]
    # 2 periods: 2030-2035, 2035-2040
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    capital = DiscountedCashFlow(
        0.07, # discount rate
        Year(2025), # base year
        periods, # vector of periods
    )
    operations = OperationalRepresentativeDays(op_days, weights)
    # no feasibility
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())

    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
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

    set_technology_model!(
        template,
        ["test_storage"],
        PSIP.StorageTechnology{EnergyReservoirStorage},
        ContinuousInvestment,
        CyclicalStorageDispatch,
        BasicDispatchFeasibility,
    )

    set_technology_model!(
        template,
        ["colocated_test"],
        ColocatedSupplyStorageTechnology{RenewableDispatch},
        ContinuousInvestment,
        CyclicalColocatedDispatch,
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
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

    res = OptimizationProblemResults(m)
    @test length(IS.Optimization.list_variable_names(res)) == 23
    @test length(IS.Optimization.list_dual_names(res)) == 0
    @test length(PSIN.get_timestamps(res)) == 48

    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
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

    set_technology_model!(
        template,
        ["test_storage"],
        PSIP.StorageTechnology{EnergyReservoirStorage},
        ContinuousInvestment,
        ChronologicalStorageDispatch,
        BasicDispatchFeasibility,
    )

    set_technology_model!(
        template,
        ["colocated_test"],
        ColocatedSupplyStorageTechnology{RenewableDispatch},
        ContinuousInvestment,
        ChronologicalColocatedDispatch,
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
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

    res = OptimizationProblemResults(m)
    @test length(IS.Optimization.list_variable_names(res)) == 23
    @test length(IS.Optimization.list_dual_names(res)) == 0
    @test length(PSIN.get_timestamps(res)) == 48

    # Weighted-energy expressions are always created, even with no requirements.
    container = PSIN.get_optimization_container(m)
    expr_keys = PSIN.get_expression_keys(container)
    @test PSIN.ExpressionKey(WeightedEnergyDemand, PSIP.Portfolio) in expr_keys
    @test PSIN.ExpressionKey(
        WeightedEnergyGeneration,
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        "BasicDispatch",
    ) in expr_keys
    @test PSIN.ExpressionKey(
        WeightedEnergyGeneration,
        PSIP.StorageTechnology{EnergyReservoirStorage},
        "ChronologicalStorageDispatch",
    ) in expr_keys
    @test PSIN.ExpressionKey(
        WeightedEnergyGeneration,
        ColocatedSupplyStorageTechnology{RenewableDispatch},
        "ChronologicalColocatedDispatch",
    ) in expr_keys
    # The aggregation expression is policy-specific, so it must NOT exist here.
    @test !any(
        IS.Optimization.get_entry_type(k) == WeightedEnergyShareGeneration for
        k in expr_keys
    )
end

@testset "check_conflict_status — DenseAxisArray" begin
    m = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(m)
    @variable(m, x)
    c1 = @constraint(m, x >= 1.0)
    c2 = @constraint(m, x <= 0.0)
    JuMP.optimize!(m)
    @test JuMP.primal_status(m) != MathOptInterface.FEASIBLE_POINT

    JuMP.compute_conflict!(m)
    @test MathOptInterface.get(m, MathOptInterface.ConflictStatus()) ==
          MathOptInterface.CONFLICT_FOUND

    dim = ["c1", "c2"]
    cc = JuMP.Containers.DenseAxisArray{JuMP.ConstraintRef}(undef, dim)
    cc["c1"] = c1
    cc["c2"] = c2
    indices = PSIN.check_conflict_status(m, cc)
    @test !isempty(indices)
end

@testset "check_conflict_status — SparseAxisArray" begin
    m = JuMP.Model(HiGHS.Optimizer)
    JuMP.set_silent(m)
    @variable(m, x)
    c1 = @constraint(m, x >= 1.0)
    c2 = @constraint(m, x <= 0.0)
    JuMP.optimize!(m)
    @test JuMP.primal_status(m) != MathOptInterface.FEASIBLE_POINT

    JuMP.compute_conflict!(m)
    @test MathOptInterface.get(m, MathOptInterface.ConflictStatus()) ==
          MathOptInterface.CONFLICT_FOUND

    sparse_cc = JuMP.Containers.SparseAxisArray(Dict(("c1",) => c1, ("c2",) => c2))
    indices = PSIN.check_conflict_status(m, sparse_cc)
    @test !isempty(indices)
end

@testset "InvestmentModel calculate_conflict=true detects infeasibility" begin
    p_5bus, op_days = test_2_zone_portfolio()
    weights = [365 * 5, 365 * 5]
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    capital = DiscountedCashFlow(0.07, Year(2025), periods)
    operations = OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())

    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
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
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )

    m = InvestmentModel(
        template,
        SingleInstanceSolve,
        p_5bus;
        optimizer=HiGHS.Optimizer,
        calculate_conflict=true,
        portfolio_to_file=false,
        store_variable_names=true,
    )

    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT

    # Force infeasibility by setting the RHS of a registered balance constraint to an
    # impossibly large demand value, so the constraint is captured in the IIS conflict dict.
    container = PSIN.get_optimization_container(m)
    jump_model = PSIN.get_jump_model(container)
    balance_key = first(
        k for k in keys(PSIN.get_constraints(container)) if
        IS.Optimization.get_entry_type(k) == PSIN.MultiRegionBalanceConstraint
    )
    balance_con = PSIN.get_constraints(container)[balance_key]
    JuMP.set_normalized_rhs(first(balance_con), 1e18)

    @test solve!(m; export_optimization_problem=false) == PSIN.RunStatus.FAILED
    @test !isempty(get_infeasibility_conflict(container))
end

@testset "Build and solve hydro portfolio with BasicDispatchWithBudget" begin
    p_hydro, op_days = test_hydro_portfolio()
    weights = [365 * 5, 365 * 5]
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    capital = DiscountedCashFlow(0.07, Year(2025), periods)
    operations = OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())

    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
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
        ["hydro"],
        PSIP.SupplyTechnology{PSY.HydroDispatch},
        ContinuousInvestment,
        BasicDispatchWithBudget,
        BasicDispatchFeasibility,
    )

    model = InvestmentModel(
        template,
        SingleInstanceSolve,
        p_hydro,
        nothing;
        optimizer=HiGHS.Optimizer,
        store_variable_names=true,
    )

    mktempdir() do path
        status = build!(model; output_dir=path)
        @test status == IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT

        container = PSIN.get_optimization_container(model)

        @test haskey(
            PSIN.get_constraints(container),
            PSIN.ConstraintKey(
                PSIN.ActivePowerLimitsConstraint,
                PSIP.SupplyTechnology{PSY.HydroDispatch},
                "BasicDispatchWithBudget",
            ),
        )

        @test haskey(
            PSIN.get_constraints(container),
            PSIN.ConstraintKey(
                HydroEnergyBudgetConstraint,
                PSIP.SupplyTechnology{PSY.HydroDispatch},
                "BasicDispatchWithBudget",
            ),
        )

        run_status = solve!(model; output_dir=path)
        @test run_status == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    end
end

@testset "Hydro budget constraint satisfied with 0.05 factor" begin
    p_tight, op_days = test_constrained_hydro_portfolio()
    weights = [365 * 5, 365 * 5]
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    capital = DiscountedCashFlow(0.07, Year(2025), periods)
    operations = OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())

    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
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
        ["hydro"],
        PSIP.SupplyTechnology{PSY.HydroDispatch},
        ContinuousInvestment,
        BasicDispatchWithBudget,
        BasicDispatchFeasibility,
    )

    set_technology_model!(
        template,
        ["backup_thermal"],
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )

    model = InvestmentModel(
        template,
        SingleInstanceSolve,
        p_tight,
        nothing;
        optimizer=HiGHS.Optimizer,
        store_variable_names=true,
    )

    mktempdir() do path
        build!(model; output_dir=path)
        run_status = solve!(model; output_dir=path)
        @test run_status == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

        hydro_df = read_variable(
            model,
            PSIN.VariableKey(
                ActivePowerVariable,
                PSIP.SupplyTechnology{PSY.HydroDispatch},
                "BasicDispatchWithBudget",
            ),
        )

        cap_df = read_expression(
            model,
            PSIN.ExpressionKey(
                CumulativeCapacity,
                PSIP.SupplyTechnology{PSY.HydroDispatch},
                "ContinuousInvestment",
            ),
        )

        hydro_rows = filter(r -> r.name == "hydro", hydro_df)
        cap_rows   = filter(r -> r.name == "hydro", cap_df)

        budget_factor = 0.05
        hours_per_period = 24
        tol = 1e-4

        dispatch_p1 = sum(filter(r -> r.time_index in 1:24, hydro_rows).value)
        cap_p1 = only(filter(r -> r.time_index == 1, cap_rows)).value
        @test dispatch_p1 <= cap_p1 * budget_factor * hours_per_period + tol

        dispatch_p2 = sum(filter(r -> r.time_index in 25:48, hydro_rows).value)
        cap_p2 = only(filter(r -> r.time_index == 2, cap_rows)).value
        @test dispatch_p2 <= cap_p2 * budget_factor * hours_per_period + tol
    end
end

@testset "Build and solve hydro portfolio with BasicDispatch" begin
    p_hydro, op_days = test_hydro_basic_dispatch_portfolio()
    weights = [365 * 5, 365 * 5]
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    capital = DiscountedCashFlow(0.07, Year(2025), periods)
    operations = OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())

    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
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
        ["hydro"],
        PSIP.SupplyTechnology{PSY.HydroDispatch},
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )

    model = InvestmentModel(
        template,
        SingleInstanceSolve,
        p_hydro,
        nothing;
        optimizer=HiGHS.Optimizer,
        store_variable_names=true,
    )

    mktempdir() do path
        status = build!(model; output_dir=path)
        @test status == IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT

        container = PSIN.get_optimization_container(model)

        @test haskey(
            PSIN.get_constraints(container),
            PSIN.ConstraintKey(
                PSIN.ActivePowerLimitsConstraint,
                PSIP.SupplyTechnology{PSY.HydroDispatch},
                "BasicDispatch",
            ),
        )

        run_status = solve!(model; output_dir=path)
        @test run_status == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

        # Verify cap factor constraint is respected: P[t] <= 0.8 * capacity
        cap_factor = 0.8
        hydro_df = read_variable(
            model,
            PSIN.VariableKey(
                PSIN.ActivePowerVariable,
                PSIP.SupplyTechnology{PSY.HydroDispatch},
                "BasicDispatch",
            ),
        )
        cap_df = read_expression(
            model,
            PSIN.ExpressionKey(
                PSIN.CumulativeCapacity,
                PSIP.SupplyTechnology{PSY.HydroDispatch},
                "ContinuousInvestment",
            ),
        )
        hydro_rows = filter(r -> r.name == "hydro", hydro_df)
        cap_rows = filter(r -> r.name == "hydro", cap_df)
        tol = 1e-4

        cap_p1 = only(filter(r -> r.time_index == 1, cap_rows)).value
        dispatch_p1_max = maximum(filter(r -> r.time_index in 1:24, hydro_rows).value)
        @test dispatch_p1_max <= cap_factor * cap_p1 + tol

        cap_p2 = only(filter(r -> r.time_index == 2, cap_rows)).value
        dispatch_p2_max = maximum(filter(r -> r.time_index in 25:48, hydro_rows).value)
        @test dispatch_p2_max <= cap_factor * cap_p2 + tol
    end
end

@testset "Build and solve 2 Zone Portfolio with EnergyShareRequirement" begin
    p_5bus, op_days = test_2_zone_portfolio()

    # Attach an energy-share policy to the existing portfolio: wind must supply at
    # least 30% of Zone_2 demand over the operational horizon.
    wind = PSIP.get_technology(
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        p_5bus,
        "wind",
    )
    zone2 = only(
        z for z in PSIP.get_regions(PSIP.Zone, p_5bus) if PSIP.get_name(z) == "Zone_2"
    )

    fraction = 0.3
    esr = PSIP.EnergyShareRequirements(;
        name="wind_share",
        id=1,
        available=true,
        target_year=2030,
        generation_fraction_requirement=fraction,
        eligible_resources=[wind],
        eligible_regions=[zone2],
    )
    PSIP.add_requirement!(p_5bus, esr)

    weights = [365 * 5, 365 * 5]
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    capital = DiscountedCashFlow(0.07, Year(2025), periods)
    operations = OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())

    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
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

    # NEW: register the requirement model
    set_requirement_model!(
        template,
        ["wind_share"],
        PSIP.EnergyShareRequirements,
        RequirementEnergyShare,
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
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

    container = PSIN.get_optimization_container(m)
    @test haskey(
        PSIN.get_constraints(container),
        PSIN.ConstraintKey(
            PSIN.EnergyShareRequirementConstraint,
            PSIP.EnergyShareRequirements,
        ),
    )

    # The policy targets target_year=2030, which maps to the first investment period
    # (2030-2034) -> operational slice op_ix=1 -> time steps 1:24. Both sides of the
    # constraint carry the same representative-day weight for op_ix=1, so the weight
    # cancels and the check reduces to comparing 2030 wind generation against the
    # 2030 Zone_2 demand.
    wind_df = read_variable(
        m,
        PSIN.VariableKey(
            ActivePowerVariable,
            PSIP.SupplyTechnology{PSY.RenewableDispatch},
            "BasicDispatch",
        ),
    )
    wind_rows = filter(r -> r.name == "wind", wind_df)
    total_wind_2030 = sum(filter(r -> r.time_index in 1:24, wind_rows).value)

    demand2 = PSIP.get_technology(PSIP.DemandRequirement{PSY.PowerLoad}, p_5bus, "demand2")
    d_2030 = IS.get_time_series(
        IS.SingleTimeSeries, demand2, "ops_demand"; year="2030", rep_day=1,
    )
    total_demand_2030 = sum(TimeSeries.values(d_2030.data))

    tol = 1e-4
    @test total_wind_2030 >= fraction * total_demand_2030 - tol

    # --- Weighted-energy expressions -------------------------------------------------
    # op_ix=1 (2030 representative day) carries weight 365*5.
    weight_1 = 365 * 5

    # WeightedEnergyGeneration[wind, op_ix=1] == weight * Σ_t P[wind, t in 1:24].
    weg_df = read_expression(
        m,
        PSIN.ExpressionKey(
            WeightedEnergyGeneration,
            PSIP.SupplyTechnology{PSY.RenewableDispatch},
            "BasicDispatch",
        ),
    )
    weg_wind_1 =
        only(filter(r -> r.name == "wind" && r.time_index == 1, weg_df)).value
    @test isapprox(weg_wind_1, weight_1 * total_wind_2030; atol=1e-2)

    # WeightedEnergyDemand[Zone_2, op_ix=1] == weight * Σ ops_demand (demand2 is Zone_2).
    wed_df = read_expression(
        m,
        PSIN.ExpressionKey(WeightedEnergyDemand, PSIP.Portfolio),
    )
    wed_zone2_1 =
        only(filter(r -> r.name == "Zone_2" && r.time_index == 1, wed_df)).value
    @test isapprox(wed_zone2_1, weight_1 * total_demand_2030; atol=1e-2)

    # WeightedEnergyShareGeneration["wind_share", op_ix=1] == WEG[wind, op_ix=1]
    # (single eligible resource).
    wesg_df = read_expression(
        m,
        PSIN.ExpressionKey(
            WeightedEnergyShareGeneration,
            PSIP.EnergyShareRequirements,
        ),
    )
    wesg_1 =
        only(filter(r -> r.name == "wind_share" && r.time_index == 1, wesg_df)).value
    @test isapprox(wesg_1, weg_wind_1; atol=1e-2)
end
