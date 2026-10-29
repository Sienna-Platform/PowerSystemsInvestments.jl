function _multi_region_supply_models()
    weights = [365, 365]
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    capital = DiscountedCashFlow(0.07, Year(2025), periods)
    feasibility = RepresentativePeriods(Vector{Vector{Dates}}())
    return capital, weights, feasibility
end

function _set_multi_region_supply_models!(template::InvestmentModelTemplate)
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
    return
end

# Each region must receive the dispatch of its own variable and nothing from the others, and
# the capacity limit must apply to the total built over all regions.
function _test_multi_region_wind(model::InvestmentModel, region_names::Vector{String})
    wind_type = PSIP.SupplyTechnology{PSY.RenewableDispatch}
    wind_names = ["wind" * PSIN.TECHNOLOGY_REGION_DELIMITER * r for r in region_names]
    container = PSIN.get_optimization_container(model)
    time_mapping = PSIN.get_time_mapping(container)

    build = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        wind_type,
        "ContinuousInvestment",
    )
    dispatch =
        PSIN.get_variable(container, PSIN.ActivePowerVariable(), wind_type, "BasicDispatch")
    @test sort(axes(build)[1]) == sort(wind_names)
    @test sort(axes(dispatch)[1]) == sort(wind_names)

    balance = PSIN.get_expression(container, PSIN.EnergyBalance(), PSIP.Portfolio)
    for t in PSIN.get_time_steps(time_mapping)
        for (wind_name, region_name) in zip(wind_names, region_names), r in region_names
            expected = 0.0
            if r == region_name
                expected = 1.0
            end
            @test JuMP.coefficient(balance[r, t], dispatch[wind_name, t]) == expected
        end
    end

    max_capacity = PSIN.get_constraint(
        container,
        PSIN.MaximumCumulativeCapacity(),
        wind_type,
        "ContinuousInvestment",
    )
    @test axes(max_capacity)[1] == ["wind"]
    for t in PSIN.get_investment_time_steps(time_mapping), wind_name in wind_names
        @test JuMP.normalized_coefficient(max_capacity["wind", t], build[wind_name, 1]) ==
              1.0
    end
    return
end

@testset "Supply technology in multiple zones" begin
    p_5bus, op_days = test_2_zone_portfolio()
    capital, weights, feasibility = _multi_region_supply_models()
    wind = PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p_5bus, "wind")
    zones = collect(PSIP.get_regions(PSIP.Zone, p_5bus))
    PSIP.set_region!(wind, zones)
    zone_names = PSIP.get_name.(zones)

    @test PSIN.get_variable_names(wind) ==
          ["wind" * PSIN.TECHNOLOGY_REGION_DELIMITER * z for z in zone_names]

    template = InvestmentModelTemplate(
        capital,
        OperationalRepresentativeDays(op_days, weights),
        feasibility,
        TransportModel(MultiRegionBalanceModel),
    )
    _set_multi_region_supply_models!(template)
    set_technology_model!(
        template,
        ["test_branch"],
        PSIP.AggregateTransportTechnology{PSY.ACBranch},
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
    _test_multi_region_wind(m, zone_names)
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED

    # Results are reported per region.
    build_df = read_variable(
        m,
        PSIN.VariableKey(
            PSIN.BuildCapacity,
            PSIP.SupplyTechnology{PSY.RenewableDispatch},
            "ContinuousInvestment",
        ),
    )
    @test sort(unique(build_df.name)) ==
          sort(["wind" * PSIN.TECHNOLOGY_REGION_DELIMITER * z for z in zone_names])
end

@testset "Supply technology in multiple nodes" begin
    p_5bus, op_days = test_2_zone_portfolio()
    capital, weights, feasibility = _multi_region_supply_models()

    nodes = [PSIP.Node(; name="Node_1", id=1), PSIP.Node(; name="Node_2", id=2)]
    for node in nodes
        PSIP.add_region!(p_5bus, node)
    end
    node_names = PSIP.get_name.(nodes)

    wind = PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p_5bus, "wind")
    PSIP.set_region!(wind, nodes)
    for name in ["cheap_thermal", "expensive_thermal"]
        thermal =
            PSIP.get_technology(PSIP.SupplyTechnology{PSY.ThermalStandard}, p_5bus, name)
        PSIP.set_region!(thermal, [nodes[1]])
    end
    for (name, node) in zip(["demand1", "demand2"], nodes)
        demand = PSIP.get_technology(PSIP.DemandRequirement{PSY.PowerLoad}, p_5bus, name)
        PSIP.set_region!(demand, [node])
    end

    line = PSIP.NodalACTransportTechnology{PSY.ACBranch}(;
        name="test_nodal_branch",
        start_node=nodes[1],
        end_node=nodes[2],
        capacity_limits=(min=0, max=1000),
        capital_costs=PSIP.CapitalCost(LinearCurve(5000.0), 0.0),
        available=true,
        power_systems_type="ACBranch",
        id=2,
        financial_data=PSIP.TechnologyFinancialData(;
            capital_recovery_period=30,
            technology_base_year=2025,
            debt_fraction=0.6,
            debt_rate=0.04,
            return_on_equity=0.10,
            tax_rate=0.21,
        ),
    )
    PSIP.add_technology!(p_5bus, line)

    template = InvestmentModelTemplate(
        capital,
        OperationalRepresentativeDays(op_days, weights),
        feasibility,
        TransportModel(NodalBalanceModel),
    )
    _set_multi_region_supply_models!(template)
    set_technology_model!(
        template,
        ["test_nodal_branch"],
        PSIP.NodalACTransportTechnology{PSY.ACBranch},
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
    _test_multi_region_wind(m, node_names)
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Multi-region supply technology validation" begin
    p_5bus, _ = test_2_zone_portfolio()
    wind = PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p_5bus, "wind")

    # A technology in a single region keeps its own name and has no restrictions.
    @test PSIN.get_variable_names(wind) == ["wind"]
    @test isnothing(PSIN.check_multi_region_technology(wind, 100.0))

    PSIP.set_region!(wind, collect(PSIP.get_regions(PSIP.Zone, p_5bus)))
    @test isnothing(PSIN.check_multi_region_technology(wind, 0.0))
    # Existing capacity cannot be assigned to a region.
    @test_throws ErrorException PSIN.check_multi_region_technology(wind, 100.0)
    # Neither can a minimum capacity limit.
    PSIP.set_capacity_limits!(wind, (min=10.0, max=1e8))
    @test_throws ErrorException PSIN.check_multi_region_technology(wind, 0.0)
end
