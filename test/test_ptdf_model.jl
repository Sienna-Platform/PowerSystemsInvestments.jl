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
    return m
end

# Coefficients of an expression by variable name, so expressions of two models can be compared
_terms_by_name(expression) =
    Dict(JuMP.name(var) => coef for (coef, var) in JuMP.linear_terms(expression))

@testset "Nodal injections are the same under the PTDF model" begin
    nodal = PSIN.get_optimization_container(_two_node_model(NodalBalanceModel))
    ptdf = PSIN.get_optimization_container(_two_node_model(NodalPTDFModel))
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

const PTDF_LINE_TYPE = PSIP.NodalACTransportTechnology{PSY.Line}

function _ptdf_line(name, from, to; reactance=0.1, unit_size=1.0, max_capacity=1000.0)
    return PTDF_LINE_TYPE(;
        name=name,
        start_node=from,
        end_node=to,
        reactance=reactance,
        unit_size=unit_size,
        capacity_limits=(min=0, max=max_capacity),
        capital_costs=PSIP.CapitalCost(LinearCurve(5000.0), 0.0),
        available=true,
        power_systems_type="Line",
        id=1,
        financial_data=PSIP.TechnologyFinancialData(;
            capital_recovery_period=30,
            technology_base_year=2025,
            debt_fraction=0.6,
            debt_rate=0.04,
            return_on_equity=0.10,
            tax_rate=0.21,
        ),
    )
end

# Four nodes A (reference) to D, with lines given as (name, from, to, formulation, keywords).
# Line "1" of the base system is the existing line of the technology named "ab_existing".
function _ptdf_network_data(lines; tol=0.0)
    portfolio, op_days = test_2_zone_portfolio()
    sys = build_system(PSITestSystems, "c_sys5_re")
    set_units_base_system!(sys, "NATURAL_UNITS")
    PSIP.set_base_system!(portfolio, sys)
    nodes = Dict(
        n => PSIP.Node(;
            name=n,
            id=i,
            bus_type=(n == "A" ? PSY.ACBusTypes.REF : PSY.ACBusTypes.PQ),
        ) for (i, n) in enumerate(("A", "B", "C", "D"))
    )
    for node in values(nodes)
        PSIP.add_region!(portfolio, node)
    end
    names_by_formulation = Dict{DataType, Vector{String}}()
    for (name, from, to, formulation, kwargs) in lines
        line = _ptdf_line(name, nodes[from], nodes[to]; kwargs...)
        PSIP.add_technology!(portfolio, line)
        if name == "ab_existing"
            PSIP.add_supplemental_attribute!(
                portfolio,
                line,
                PSIP.ExistingDevices(; existing_devices=["1"]),
            )
        end
        push!(get!(names_by_formulation, formulation, String[]), name)
    end
    template = InvestmentModelTemplate(
        DiscountedCashFlow(
            0.07,
            Year(2025),
            [
                (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
                (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
            ],
        ),
        OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(NodalPTDFModel),
    )
    for (formulation, names) in names_by_formulation
        set_technology_model!(
            template,
            names,
            PTDF_LINE_TYPE,
            formulation,
            BasicDispatch,
            BasicDispatchFeasibility,
        )
    end
    return PSIN.PTDFNetworkData(portfolio, template; tol=tol), portfolio
end

@testset "PTDF network branches" begin
    network, portfolio = _ptdf_network_data([
        ("ab_existing", "A", "B", ContinuousInvestment, (;)),
        ("ab_new", "A", "B", ContinuousInvestment, (;)),
        ("ba_units", "B", "A", IntegerInvestment, (unit_size=100.0, max_capacity=300.0)),
        ("bc_new", "B", "C", ContinuousInvestment, (;)),
        ("cd_binary", "C", "D", BinaryInvestment, (unit_size=200.0,)),
    ])
    existing = PSIP.get_technology(PTDF_LINE_TYPE, portfolio, "ab_existing")
    @test PSIP.get_existing_capacity_mw(portfolio, existing) > 0.0
    b = 230.0^2 / 0.1

    # The existing line and the continuous candidate share the A-B corridor, whose
    # susceptance is that of the existing line only
    corridor = only(network.merged_corridors)
    @test corridor.name == "A_B"
    @test corridor.arc == ("A", "B")
    @test corridor.susceptance ≈ b
    @test corridor.fixed_capacity == 0.0
    @test sort([t.name for t in corridor.technologies]) == ["ab_existing", "ab_new"]

    # A continuous candidate without existing capacity on its corridor gets its own branch
    new_corridor = only(network.new_corridors)
    @test new_corridor.name == "bc_new"
    @test new_corridor.arc == ("B", "C")

    # Each unit of a discrete candidate is a branch: three for the integer line on A-B and one
    # for the binary line, although its capacity limit allows more
    @test [l.name for l in network.unit_lines] == ["ba_units_unit_1", "ba_units_unit_2", "ba_units_unit_3", "cd_binary_unit_1"]
    @test all(l.arc == ("B", "A") for l in network.unit_lines[1:3])
    @test [l.unit_size for l in network.unit_lines] == [100.0, 100.0, 100.0, 200.0]

    ptdf = network.ptdf
    @test ptdf.axes[2] == [
        "A_B",
        "bc_new",
        "ba_units_unit_1",
        "ba_units_unit_2",
        "ba_units_unit_3",
        "cd_binary_unit_1",
    ]
    # Parallel branches split the corridor flow by susceptance; the unit lines run B to A
    for node in ptdf.axes[1], unit in ("ba_units_unit_1", "ba_units_unit_3")
        @test ptdf[unit, node] ≈ -ptdf["A_B", node]
    end
end

@testset "PTDF network branch checks" begin
    # An integer line with the default capacity limit would need 1e8 unit lines
    @test_throws ErrorException _ptdf_network_data([
        ("ab", "A", "B", IntegerInvestment, (max_capacity=1e8,)),
    ])
    @test_throws ErrorException _ptdf_network_data([
        ("ab", "A", "B", IntegerInvestment, (unit_size=0.0,)),
    ])
    @test_logs (:warn, r"susceptance per MW") match_mode = :any _ptdf_network_data([
        ("ab_existing", "A", "B", ContinuousInvestment, (;)),
        ("ab_new", "A", "B", ContinuousInvestment, (reactance=0.2,)),
    ])
end

@testset "PTDF network data is built with the model" begin
    m = _two_node_model(NodalPTDFModel)
    network = PSIN.get_network_data(PSIN.get_transport_model(PSIN.get_template(m)))
    @test network.ptdf.axes == (["Node_1", "Node_2"], ["nodal_line"])
    @test only(network.new_corridors).name == "nodal_line"
    @test isnothing(
        PSIN.get_network_data(
            PSIN.get_transport_model(PSIN.get_template(_two_node_model(NodalBalanceModel))),
        ),
    )
end
