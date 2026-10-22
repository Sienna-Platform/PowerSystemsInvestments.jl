const TRANSMISSION_UNIT_SIZE = 250.0

function _transmission_template(transport)
    p_5bus, op_days = test_2_zone_portfolio()
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), periods),
        OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(transport, use_slacks=false),
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
    return template, p_5bus
end

# Zonal line between the two zones of the test portfolio
function _aggregate_line_model(formulation)
    template, p_5bus = _transmission_template(MultiRegionBalanceModel)
    line_type = PSIP.AggregateTransportTechnology{PSY.ACBranch}
    line = PSIP.get_technology(line_type, p_5bus, "test_branch")
    PSIP.set_unit_size!(line, TRANSMISSION_UNIT_SIZE)
    set_technology_model!(
        template,
        ["test_branch"],
        line_type,
        formulation,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    return template, p_5bus, line_type, "test_branch"
end

# Nodal line between two nodes holding the zones' technologies
function _nodal_line_model(formulation)
    template, p_5bus = _transmission_template(NodalBalanceModel)
    nodes = [PSIP.Node(; name="Node_1", id=1), PSIP.Node(; name="Node_2", id=2)]
    for node in nodes
        PSIP.add_region!(p_5bus, node)
    end
    for (type, name, node) in (
        (PSIP.SupplyTechnology{PSY.RenewableDispatch}, "wind", 2),
        (PSIP.SupplyTechnology{PSY.ThermalStandard}, "cheap_thermal", 1),
        (PSIP.SupplyTechnology{PSY.ThermalStandard}, "expensive_thermal", 1),
        (PSIP.DemandRequirement{PSY.PowerLoad}, "demand1", 1),
        (PSIP.DemandRequirement{PSY.PowerLoad}, "demand2", 2),
    )
        PSIP.set_region!(PSIP.get_technology(type, p_5bus, name), [nodes[node]])
    end
    line_type = PSIP.NodalACTransportTechnology{PSY.ACBranch}
    line = line_type(;
        name="nodal_line",
        start_node=nodes[1],
        end_node=nodes[2],
        capacity_limits=(min=0, max=1000),
        unit_size=TRANSMISSION_UNIT_SIZE,
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
    set_technology_model!(
        template,
        ["nodal_line"],
        line_type,
        formulation,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    return template, p_5bus, line_type, "nodal_line"
end

function _build_line_model(make_model, formulation)
    template, p_5bus, line_type, name = make_model(formulation)
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
    return m, line_type, name
end

@testset "Transmission technologies with discrete investment" begin
    for (label, make_model) in
        (("zonal", _aggregate_line_model), ("nodal", _nodal_line_model))
        @testset "$label line" begin
            m_continuous, line_type, name =
                _build_line_model(make_model, ContinuousInvestment)
            continuous_container = PSIN.get_optimization_container(m_continuous)
            continuous_build = PSIN.get_variable(
                continuous_container,
                PSIN.BuildCapacity(),
                line_type,
                "ContinuousInvestment",
            )
            mw_cost = JuMP.coefficient(
                JuMP.objective_function(PSIN.get_jump_model(continuous_container)),
                continuous_build[name, 1],
            )
            continuous_capacity = PSIN.get_expression(
                continuous_container,
                PSIN.CumulativeCapacity(),
                line_type,
                "ContinuousInvestment",
            )
            @test JuMP.coefficient(
                continuous_capacity[name, 2],
                continuous_build[name, 1],
            ) == 1.0
            @test !JuMP.is_integer(continuous_build[name, 1])

            for (formulation, is_discrete) in
                ((BinaryInvestment, JuMP.is_binary), (IntegerInvestment, JuMP.is_integer))
                m, _, _ = _build_line_model(make_model, formulation)
                container = PSIN.get_optimization_container(m)
                meta = string(formulation)
                build = PSIN.get_variable(container, PSIN.BuildCapacity(), line_type, meta)
                capacity = PSIN.get_expression(
                    container,
                    PSIN.CumulativeCapacity(),
                    line_type,
                    meta,
                )
                for t in PSIN.get_investment_time_steps(PSIN.get_time_mapping(container))
                    @test is_discrete(build[name, t])
                    @test JuMP.coefficient(capacity[name, t], build[name, 1]) ==
                          TRANSMISSION_UNIT_SIZE
                end
                # Per-unit cost is the per-MW cost times the unit size
                unit_cost = JuMP.coefficient(
                    JuMP.objective_function(PSIN.get_jump_model(container)),
                    build[name, 1],
                )
                @test unit_cost ≈ TRANSMISSION_UNIT_SIZE * mw_cost

                @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
                built = JuMP.value.(build[name, :])
                @test all(isapprox.(built, round.(built); atol=1e-6))
                flow = PSIN.get_variable(
                    container,
                    PSIN.FlowActivePowerVariable(),
                    line_type,
                    "BasicDispatch",
                )
                @test maximum(abs.(JuMP.value.(flow.data))) <=
                      TRANSMISSION_UNIT_SIZE * sum(round.(built)) + 1e-6
                if formulation == BinaryInvestment
                    @test sum(built) <= 1.0 + 1e-6
                    single_unit = PSIN.get_constraint(
                        container,
                        PSIN.SingleUnitInvestmentConstraint(),
                        line_type,
                        meta,
                    )
                    @test JuMP.normalized_rhs(single_unit[name]) == 1.0
                end
            end
        end
    end
end
