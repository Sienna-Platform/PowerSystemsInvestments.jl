@testset "Build and solve" begin
    p_5bus, op_days = test_data()

    weights = [365 * 5, 365 * 5]

    capital = DiscountedCashFlow(
        0.07,
        Year(2025),
        [
            (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
            (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
        ],
    )
    operations = PSIN.OperationalRepresentativeDays(op_days, weights)
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
end

@testset "Test OptimizationProblemResults interfaces" begin
    p_5bus, op_days = test_data()

    weights = [365 * 5, 365 * 5]

    capital = DiscountedCashFlow(
        0.07,
        Year(2025),
        [
            (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
            (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
        ],
    )
    operations = PSIN.OperationalRepresentativeDays(op_days, weights)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())

    template = InvestmentModelTemplate(
        capital,
        operations,
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(MultiRegionBalanceModel, use_slacks=false),
    )

    demand_model = PSIN.TechnologyModel(
        PSIP.DemandRequirement{PSY.PowerLoad},
        PSIN.StaticLoadInvestment,
        PSIN.BasicDispatch,
        PSIN.BasicDispatchFeasibility,
    )

    vre_model = PSIN.TechnologyModel(
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        PSIN.ContinuousInvestment,
        PSIN.BasicDispatch,
        PSIN.BasicDispatchFeasibility,
    )

    thermal_modelA = PSIN.TechnologyModel(
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSIN.ContinuousInvestment,
        PSIN.BasicDispatch,
        PSIN.BasicDispatchFeasibility,
    )

    thermal_modelB = PSIN.TechnologyModel(
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        PSIN.IntegerInvestment,
        PSIN.BasicDispatch,
        PSIN.BasicDispatchFeasibility,
    )

    ac_model = PSIN.TechnologyModel(
        PSIP.ACTransportTechnology{PSY.ACBranch},
        PSIN.ContinuousInvestment,
        PSIN.BasicDispatch,
        PSIN.BasicDispatchFeasibility,
    )

    m = InvestmentModel(
        template,
        PSIN.SingleInstanceSolve,
        p_5bus;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
        store_variable_names=true,
    )

    tech_models = template.technology_models
    tech_models[thermal_modelA] = ["cheap_thermal", "expensive_thermal"]
    tech_models[vre_model] = ["wind"]
    tech_models[demand_model] = ["demand1", "demand2"]

    branch_models = template.branch_models
    branch_models[ac_model] = ["test_branch"]

    build!(m; output_dir=mktempdir(; cleanup=true))

    # TODO: Fix Results Store!!!
    #=
    res = OptimizationProblemResults(m)
    @test length(IS.Optimization.list_variable_names(res)) == 4
    @test length(IS.Optimization.list_dual_names(res)) == 0
    #@test get_model_base_power(res) == 100.0
    @test isa(IS.Optimization.get_objective_value(res), Float64)
    @test isa(res.variable_values, Dict{PSIN.VariableKey, DataFrames.DataFrame})
    #@test isa(IS.Optimization.read_variables(res), Dict{String, DataFrames.DataFrame})
    @test isa(IS.Optimization.get_total_cost(res), Float64)
    @test isa(IS.Optimization.get_optimizer_stats(res), DataFrames.DataFrame)
    @test isa(res.dual_values, Dict{PSIN.ConstraintKey, DataFrames.DataFrame})
    @test isa(IS.Optimization.read_duals(res), Dict{String, DataFrames.DataFrame})
    #@test isa(PSIN.get_resolution(res), Dates.TimePeriod)
    @test isa(IS.Optimization.get_source_data(res), PSIP.Portfolio)
    @test length(PSIN.get_timestamps(res)) == 48
    =#
end
