@testset "Build and solve 2 Zone Portfolio" begin
    p_5bus, op_days = test_2_zone_portfolio()
    # 2 representative days (24 hours each), one per period, with per-year weights
    weights = [365, 365]
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
        TransportModel(MultiRegionBalanceModel),
    )

    set_technology_model!(
        template,
        ["demand1", "demand2"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
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

    # Storage charge and discharge must appear in the balance of the region it is in.
    container = PSIN.get_optimization_container(m)
    balance = PSIN.get_expression(container, PSIN.EnergyBalance(), PSIP.Portfolio)
    storage_type = PSIP.StorageTechnology{EnergyReservoirStorage}
    storage = PSIP.get_technology(storage_type, p_5bus, "test_storage")
    storage_region = PSIP.get_name(only(PSIP.get_region(storage)))
    for (var_type, coefficient) in
        ((PSIN.ActiveOutPowerVariable, 1.0), (PSIN.ActiveInPowerVariable, -1.0))
        variable = PSIN.get_variable(
            container,
            var_type(),
            storage_type,
            "CyclicalStorageDispatch",
        )
        for t in PSIN.get_time_steps(PSIN.get_time_mapping(container))
            @test JuMP.coefficient(
                balance[storage_region, t],
                variable["test_storage", t],
            ) == coefficient
        end
    end

    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

    res = OptimizationProblemResults(m)
    @test length(IS.Optimization.list_variable_names(res)) == 23
    @test length(IS.Optimization.list_dual_names(res)) == 0
    @test length(PSIN.get_timestamps(res)) == 48

    template = InvestmentModelTemplate(
        capital,
        operations,
        feasibility,
        TransportModel(MultiRegionBalanceModel),
    )

    set_technology_model!(
        template,
        ["demand1", "demand2"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
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
    # The aggregation expressions are policy-specific, so they must NOT exist here.
    @test !any(
        IS.Optimization.get_entry_type(k) in
        (WeightedEnergyShareGeneration, WeightedEnergyShareDemand) for k in expr_keys
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
    weights = [365, 365]
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
        TransportModel(MultiRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["demand1", "demand2"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
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

    @test solve!(
        m;
        export_optimization_problem=false,
        console_level=Logging.AboveMaxLevel,
    ) == PSIN.RunStatus.FAILED
    conflict = get_infeasibility_conflict(container)
    @test !isempty(conflict)

    # The conflict table must print with the installed PrettyTables version.
    key, indices = first(conflict)
    table = sprint(PSIN._print_conflict_table, key, indices)
    @test occursin(string(key), table)
end

@testset "Build and solve hydro portfolio with BasicDispatchWithBudget" begin
    p_hydro, op_days = test_hydro_portfolio()
    weights = [365, 365]
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
        TransportModel(SingleRegionBalanceModel),
    )

    set_technology_model!(
        template,
        ["demand"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
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
        portfolio_to_file=false,
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

        # Hydro is the only supply, so its daily budget of 0.5 × 24 hours of capacity must
        # cover the daily demand of 2400 MWh (2030) and 2880 MWh (2035)
        capacity = read_expression(
            model,
            PSIN.ExpressionKey(
                CumulativeCapacity,
                PSIP.SupplyTechnology{PSY.HydroDispatch},
                "ContinuousInvestment",
            ),
        )
        @test sort(capacity, :time_index).value ≈ [200.0, 240.0]
        dispatch = read_variable(
            model,
            PSIN.VariableKey(
                ActivePowerVariable,
                PSIP.SupplyTechnology{PSY.HydroDispatch},
                "BasicDispatchWithBudget",
            ),
        )
        @test sum(dispatch[dispatch.time_index .<= 24, :value]) ≈ 2400.0
        @test sum(dispatch[dispatch.time_index .> 24, :value]) ≈ 2880.0
    end
end

@testset "Hydro budget constraint satisfied with 0.05 factor" begin
    p_tight, op_days = test_constrained_hydro_portfolio()
    # Free hydro is built to its 500 MW limit, so its energy is limited by the budget
    hydro = PSIP.get_technology(PSIP.SupplyTechnology{PSY.HydroDispatch}, p_tight, "hydro")
    PSIP.set_capital_costs!(hydro, PSIP.CapitalCost(LinearCurve(0.0), 0.0))
    weights = [365, 365]
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
        TransportModel(SingleRegionBalanceModel),
    )

    set_technology_model!(
        template,
        ["demand"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
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
        portfolio_to_file=false,
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
        cap_rows = filter(r -> r.name == "hydro", cap_df)

        budget_factor = 0.05
        hours_per_period = 24
        tol = 1e-4

        dispatch_p1 = sum(filter(r -> r.time_index in 1:24, hydro_rows).value)
        cap_p1 = only(filter(r -> r.time_index == 1, cap_rows)).value
        @test cap_p1 ≈ 500.0
        @test dispatch_p1 ≈ cap_p1 * budget_factor * hours_per_period atol = tol

        dispatch_p2 = sum(filter(r -> r.time_index in 25:48, hydro_rows).value)
        cap_p2 = only(filter(r -> r.time_index == 2, cap_rows)).value
        @test cap_p2 ≈ 500.0
        @test dispatch_p2 ≈ cap_p2 * budget_factor * hours_per_period atol = tol
    end
end

@testset "Build and solve hydro portfolio with BasicDispatch" begin
    p_hydro, op_days = test_hydro_basic_dispatch_portfolio()
    weights = [365, 365]
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
        TransportModel(SingleRegionBalanceModel),
    )

    set_technology_model!(
        template,
        ["demand"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
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
        portfolio_to_file=false,
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

        # Dispatch is limited to the 0.8 capacity factor times the 0.95 availability (5%
        # forced outage) of the capacity
        cap_factor = 0.8 * 0.95
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
        @test cap_p1 ≈ 100.0 / cap_factor
        @test dispatch_p1_max ≈ cap_factor * cap_p1 atol = tol

        cap_p2 = only(filter(r -> r.time_index == 2, cap_rows)).value
        dispatch_p2_max = maximum(filter(r -> r.time_index in 25:48, hydro_rows).value)
        @test cap_p2 ≈ 120.0 / cap_factor
        @test dispatch_p2_max ≈ cap_factor * cap_p2 atol = tol
    end
end

@testset "Build and solve 2 Zone Portfolio with EnergyShareRequirement" begin
    p_5bus, op_days = test_2_zone_portfolio()

    # Attach energy-share policies to the existing portfolio: wind must supply at
    # least 150% (2030) and 160% (2035) of demand2. The requirement is attached
    # to the contributing technologies (wind on the generation side, demand2 on the
    # demand side) via each technology's `requirements` field (PSIP PR #94 model).
    wind = PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p_5bus, "wind")
    demand2 = PSIP.get_technology(PSIP.ProjectedDemand{PSY.PowerLoad}, p_5bus, "demand2")

    # Wind would supply about 130% of demand2 without the policies, so these targets bind
    fraction = 1.5
    fraction_2035 = 1.6
    esr = PSIP.EnergyShareRequirements(;
        name="wind_share",
        id=1,
        available=true,
        target_year=2030,
        generation_fraction_requirement=fraction,
    )
    # A second policy of the same type, registered through its own
    # `set_requirement_model!` call below.
    esr_2035 = PSIP.EnergyShareRequirements(;
        name="wind_share_2035",
        id=2,
        available=true,
        target_year=2035,
        generation_fraction_requirement=fraction_2035,
    )
    PSIP.add_requirement!(p_5bus, esr)
    PSIP.add_requirement!(p_5bus, esr_2035)
    PSIP.set_requirements!(wind, [esr, esr_2035])
    PSIP.set_requirements!(demand2, [esr, esr_2035])

    weights = [365, 365]
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
        TransportModel(MultiRegionBalanceModel),
    )

    set_technology_model!(
        template,
        ["demand1", "demand2"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
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

    # Register the requirement models. Models of the same type and formulation are merged
    # at build time.
    set_requirement_model!(
        template,
        ["wind_share"],
        PSIP.EnergyShareRequirements,
        RequirementEnergyShare,
    )
    set_requirement_model!(
        template,
        ["wind_share_2035"],
        PSIP.EnergyShareRequirements,
        RequirementEnergyShare,
    )
    requirement_map = PSIN.get_requirement_formulation_to_names_map(
        PSIN.get_requirement_models(template),
        p_5bus,
    )
    @test sort(requirement_map[(PSIP.EnergyShareRequirements, RequirementEnergyShare)]) ==
          ["wind_share", "wind_share_2035"]

    # A requirement can only belong to one requirement model.
    duplicated_template = deepcopy(template)
    set_requirement_model!(
        duplicated_template,
        ["wind_share"],
        PSIP.EnergyShareRequirements,
        RequirementEnergyShare,
    )
    @test_throws ErrorException PSIN.names_to_requirement_model_map(
        PSIN.get_requirement_models(duplicated_template),
    )

    # Each requirement keeps the model it was registered with.
    requirement_models =
        PSIN.names_to_requirement_model_map(PSIN.get_requirement_models(template))
    model_vector = PSIN.names_to_requirement_model_vector(
        requirement_models,
        ["wind_share", "wind_share_2035"],
    )
    @test model_vector[1] !== model_vector[2]
    @test model_vector ==
          [requirement_models["wind_share"], requirement_models["wind_share_2035"]]

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

    d_2030 = IS.get_time_series(
        IS.SingleTimeSeries,
        demand2,
        "ops_demand";
        year="2030",
        rep_day=1,
    )
    # The demand series is normalized to the peak demand
    total_demand_2030 =
        sum(TimeSeries.values(d_2030.data)) * PSIP.get_peak_demand_mw(demand2)

    @test total_wind_2030 ≈ fraction * total_demand_2030 rtol = 1e-6

    # The 2035 policy applies to the second investment period (time steps 25:48)
    total_wind_2035 = sum(filter(r -> r.time_index in 25:48, wind_rows).value)
    d_2035 = IS.get_time_series(
        IS.SingleTimeSeries,
        demand2,
        "ops_demand";
        year="2035",
        rep_day=2,
    )
    @test total_wind_2035 ≈
          fraction_2035 *
          sum(TimeSeries.values(d_2035.data)) *
          PSIP.get_peak_demand_mw(demand2) rtol = 1e-6

    # --- Weighted-energy expressions -------------------------------------------------
    # op_ix=1 (2030 representative day) carries the per-year weight 365.
    weight_1 = 365

    # WeightedEnergyGeneration[wind, op_ix=1] == weight * Σ_t P[wind, t in 1:24].
    weg_df = read_expression(
        m,
        PSIN.ExpressionKey(
            WeightedEnergyGeneration,
            PSIP.SupplyTechnology{PSY.RenewableDispatch},
            "BasicDispatch",
        ),
    )
    weg_wind_1 = only(filter(r -> r.name == "wind" && r.time_index == 1, weg_df)).value
    @test isapprox(weg_wind_1, weight_1 * total_wind_2030; atol=1e-2)

    # WeightedEnergyDemand[Zone_2, op_ix=1] == weight * Σ ops_demand (demand2 is Zone_2).
    wed_df = read_expression(m, PSIN.ExpressionKey(WeightedEnergyDemand, PSIP.Portfolio))
    wed_zone2_1 = only(filter(r -> r.name == "Zone_2" && r.time_index == 1, wed_df)).value
    @test isapprox(wed_zone2_1, weight_1 * total_demand_2030; atol=1e-2)

    # WeightedEnergyShareGeneration["wind_share", op_ix=1] == WEG[wind, op_ix=1]
    # (single eligible resource).
    wesg_df = read_expression(
        m,
        PSIN.ExpressionKey(WeightedEnergyShareGeneration, PSIP.EnergyShareRequirements),
    )
    wesg_1 = only(filter(r -> r.name == "wind_share" && r.time_index == 1, wesg_df)).value
    @test isapprox(wesg_1, weg_wind_1; atol=1e-2)

    # WeightedEnergyShareDemand["wind_share", op_ix=1] == weight * total_demand_2030
    # (single contributing load, demand2).
    wesd_df = read_expression(
        m,
        PSIN.ExpressionKey(WeightedEnergyShareDemand, PSIP.EnergyShareRequirements),
    )
    wesd_1 = only(filter(r -> r.name == "wind_share" && r.time_index == 1, wesd_df)).value
    @test isapprox(wesd_1, weight_1 * total_demand_2030; atol=1e-2)
end

function _build_thermal_investment_model(investment_formulation)
    p_5bus, op_days = test_2_zone_portfolio()
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), periods),
        OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(SingleRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["demand1"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
        StaticLoadInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["cheap_thermal"],
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["expensive_thermal"],
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        investment_formulation,
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
    return m, p_5bus
end

@testset "Supply technology with discrete investment" begin
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    m_continuous, _ = _build_thermal_investment_model(ContinuousInvestment)
    continuous_container = PSIN.get_optimization_container(m_continuous)
    continuous_build = PSIN.get_variable(
        continuous_container,
        PSIN.BuildCapacity(),
        thermal_type,
        "ContinuousInvestment",
    )
    mw_cost = JuMP.coefficient(
        JuMP.objective_function(PSIN.get_jump_model(continuous_container)),
        continuous_build["expensive_thermal", 1],
    )

    for (formulation, is_discrete) in
        ((BinaryInvestment, JuMP.is_binary), (IntegerInvestment, JuMP.is_integer))
        m, p_5bus = _build_thermal_investment_model(formulation)
        container = PSIN.get_optimization_container(m)
        unit_size = PSIP.get_unit_size(
            PSIP.get_technology(thermal_type, p_5bus, "expensive_thermal"),
        )
        meta = string(formulation)

        build = PSIN.get_variable(container, PSIN.BuildCapacity(), thermal_type, meta)
        capacity =
            PSIN.get_expression(container, PSIN.CumulativeCapacity(), thermal_type, meta)
        for t in PSIN.get_investment_time_steps(PSIN.get_time_mapping(container))
            @test is_discrete(build["expensive_thermal", t])
            # Each unit built adds unit_size MW of capacity.
            @test JuMP.coefficient(
                capacity["expensive_thermal", t],
                build["expensive_thermal", 1],
            ) == unit_size
        end

        # The cost of building one unit is the per-MW cost of the continuous formulation
        # times the unit size.
        unit_cost = JuMP.coefficient(
            JuMP.objective_function(PSIN.get_jump_model(container)),
            build["expensive_thermal", 1],
        )
        @test unit_cost ≈ unit_size * mw_cost

        @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
        if formulation == BinaryInvestment
            @test sum(JuMP.value.(build["expensive_thermal", :])) <= 1.0 + 1e-6
        end
    end

    # A discrete investment needs a positive unit size.
    thermal = PSIP.get_technology(thermal_type, test_2_zone_portfolio()[1], "cheap_thermal")
    PSIP.set_unit_size!(thermal, 0.0)
    @test_throws ErrorException PSIN.get_unit_size(
        PSIN.BuildCapacity(),
        thermal,
        IntegerInvestment(),
    )
end

@testset "Storage technology with IntegerInvestment" begin
    p_5bus, op_days = test_2_zone_portfolio()
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), periods),
        OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(SingleRegionBalanceModel),
    )
    set_technology_model!(
        template,
        ["demand1"],
        PSIP.ProjectedDemand{PSY.PowerLoad},
        StaticLoadInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    set_technology_model!(
        template,
        ["cheap_thermal"],
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    storage_type = PSIP.StorageTechnology{EnergyReservoirStorage}
    set_technology_model!(
        template,
        ["test_storage"],
        storage_type,
        IntegerInvestment,
        CyclicalStorageDispatch,
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
    storage = PSIP.get_technology(storage_type, p_5bus, "test_storage")
    # Power capacity is built in units of the discharge size and energy capacity in units of
    # the energy size.
    for (variable_type, expression_type, unit_size) in (
        (
            PSIN.BuildPowerCapacity,
            PSIN.CumulativePowerCapacity,
            PSIP.get_unit_size_discharge(storage),
        ),
        (
            PSIN.BuildEnergyCapacity,
            PSIN.CumulativeEnergyCapacity,
            PSIP.get_unit_size_energy(storage),
        ),
    )
        build =
            PSIN.get_variable(container, variable_type(), storage_type, "IntegerInvestment")
        capacity = PSIN.get_expression(
            container,
            expression_type(),
            storage_type,
            "IntegerInvestment",
        )
        @test JuMP.is_integer(build["test_storage", 1])
        @test JuMP.coefficient(capacity["test_storage", 1], build["test_storage", 1]) ==
              unit_size
    end

    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
end
