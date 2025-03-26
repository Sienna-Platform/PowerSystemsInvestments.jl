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
        PSIP.ACTransportTechnology{PSY.ACBranch},
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
        PSIP.ACTransportTechnology{PSY.ACBranch},
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
