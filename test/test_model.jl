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
