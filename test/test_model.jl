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
