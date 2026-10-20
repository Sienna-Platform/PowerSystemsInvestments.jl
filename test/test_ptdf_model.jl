# Two nodes with a line between them, holding the technologies of the 2-zone test portfolio
function _two_node_model(transport)
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
    nodes = [PSIP.Node(; name="Node_1", id=1), PSIP.Node(; name="Node_2", id=2)]
    for node in nodes
        PSIP.add_region!(p_5bus, node)
    end
    technologies = (
        (PSIP.SupplyTechnology{PSY.RenewableDispatch}, "wind", 2, ContinuousInvestment),
        (
            PSIP.SupplyTechnology{PSY.ThermalStandard},
            "cheap_thermal",
            1,
            ContinuousInvestment,
        ),
        (PSIP.DemandRequirement{PSY.PowerLoad}, "demand1", 1, StaticLoadInvestment),
        (PSIP.DemandRequirement{PSY.PowerLoad}, "demand2", 2, StaticLoadInvestment),
    )
    for (type, name, node, investment) in technologies
        PSIP.set_region!(PSIP.get_technology(type, p_5bus, name), [nodes[node]])
        set_technology_model!(
            template,
            [name],
            type,
            investment,
            BasicDispatch,
            BasicDispatchFeasibility,
        )
    end
    storage_type = PSIP.StorageTechnology{EnergyReservoirStorage}
    PSIP.set_region!(PSIP.get_technology(storage_type, p_5bus, "test_storage"), [nodes[2]])
    set_technology_model!(
        template,
        ["test_storage"],
        storage_type,
        ContinuousInvestment,
        CyclicalStorageDispatch,
        BasicDispatchFeasibility,
    )

    line_type = PSIP.NodalACTransportTechnology{PSY.ACBranch}
    line = line_type(;
        name="nodal_line",
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
    set_technology_model!(
        template,
        ["nodal_line"],
        line_type,
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
    return PSIN.get_optimization_container(m)
end

# Coefficients of an expression by variable name, so expressions of two models can be compared
_terms_by_name(expression) =
    Dict(JuMP.name(var) => coef for (coef, var) in JuMP.linear_terms(expression))

@testset "Nodal injections are the same under the PTDF model" begin
    nodal = _two_node_model(NodalBalanceModel)
    ptdf = _two_node_model(NodalPTDFModel)
    line_type = PSIP.NodalACTransportTechnology{PSY.ACBranch}
    nodal_balance = PSIN.get_expression(nodal, PSIN.EnergyBalance(), PSIP.Portfolio)
    ptdf_balance = PSIN.get_expression(ptdf, PSIN.EnergyBalance(), PSIP.Portfolio)
    @test axes(ptdf_balance) == axes(nodal_balance)

    line_flow =
        PSIN.get_variable(nodal, PSIN.FlowActivePowerVariable(), line_type, "BasicDispatch")
    line_flow_names = Set(JuMP.name.(line_flow.data))
    for node in axes(nodal_balance, 1), t in axes(nodal_balance, 2)
        nodal_terms = _terms_by_name(nodal_balance[node, t])
        # Under the nodal transport model the line adds its flow to both nodes
        @test count(in(line_flow_names), keys(nodal_terms)) == 1
        injections = filter(((name, _),) -> !in(name, line_flow_names), nodal_terms)
        @test _terms_by_name(ptdf_balance[node, t]) == injections
        @test JuMP.constant(ptdf_balance[node, t]) == JuMP.constant(nodal_balance[node, t])
    end

    # Nodes are not balanced one by one under the PTDF model
    @test !haskey(
        PSIN.get_constraints(ptdf),
        PSIN.ConstraintKey(NodalBalanceConstraint, PSIP.Portfolio),
    )
end
