const PTDF_TECHNOLOGIES = (
    (PSIP.SupplyTechnology{PSY.ThermalStandard}, "cheap_thermal", ContinuousInvestment),
    (PSIP.SupplyTechnology{PSY.ThermalStandard}, "expensive_thermal", ContinuousInvestment),
    (PSIP.SupplyTechnology{PSY.RenewableDispatch}, "wind", ContinuousInvestment),
    (PSIP.DemandRequirement{PSY.PowerLoad}, "demand1", StaticLoadInvestment),
    (PSIP.DemandRequirement{PSY.PowerLoad}, "demand2", StaticLoadInvestment),
)

const PTDF_LINE_TYPE = PSIP.NodalACTransportTechnology{PSY.Line}

function _ptdf_line(
    name,
    from,
    to;
    reactance=0.1,
    unit_size=1.0,
    max_capacity=1000.0,
    capital_cost=5000.0,
)
    return PTDF_LINE_TYPE(;
        name=name,
        start_node=from,
        end_node=to,
        reactance=reactance,
        unit_size=unit_size,
        capacity_limits=(min=0, max=max_capacity),
        capital_costs=PSIP.CapitalCost(LinearCurve(capital_cost), 0.0),
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

# Model of the 2-zone test portfolio on nodes. `placement` maps technology names to nodes (the
# first node is the reference) and `lines` are (name, from, to, reactance, existing device),
# where the existing device is a line of the base system whose rating is the line's capacity,
# so it cannot be expanded. A line without an existing device is a candidate of up to 1000 MW
# costing `candidate_cost` per MW. `ratings` overrides the rating of base system lines.
function _nodal_test_model(
    transport;
    nodes,
    placement,
    lines,
    ratings=Dict{String, Float64}(),
    use_slacks=false,
    candidate_cost=5000.0,
)
    p_5bus, op_days = test_2_zone_portfolio()
    sys = build_system(PSITestSystems, "c_sys5_re")
    set_units_base_system!(sys, "NATURAL_UNITS")
    for (device, rating) in ratings
        PSY.set_rating!(PSY.get_component(PSY.Line, sys, device), rating)
    end
    PSIP.set_base_system!(p_5bus, sys)
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), periods),
        OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods(Vector{Vector{Dates}}()),
        TransportModel(transport, use_slacks=use_slacks),
    )
    regions = Dict(
        n => PSIP.Node(;
            name=n,
            id=i,
            bus_type=(i == 1 ? PSY.ACBusTypes.REF : PSY.ACBusTypes.PQ),
        ) for (i, n) in enumerate(nodes)
    )
    for node in values(regions)
        PSIP.add_region!(p_5bus, node)
    end
    for (type, name, investment) in PTDF_TECHNOLOGIES
        PSIP.set_region!(
            PSIP.get_technology(type, p_5bus, name),
            [regions[placement[name]]],
        )
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
    PSIP.set_region!(
        PSIP.get_technology(storage_type, p_5bus, "test_storage"),
        [regions[placement["test_storage"]]],
    )
    set_technology_model!(
        template,
        ["test_storage"],
        storage_type,
        ContinuousInvestment,
        CyclicalStorageDispatch,
        BasicDispatchFeasibility,
    )

    for (name, from, to, reactance, device) in lines
        if isnothing(device)
            line = _ptdf_line(
                name,
                regions[from],
                regions[to];
                reactance=reactance,
                capital_cost=candidate_cost,
            )
            PSIP.add_technology!(p_5bus, line)
            continue
        end
        rating = PSY.get_rating(PSY.get_component(PSY.Line, sys, device))
        line = _ptdf_line(
            name,
            regions[from],
            regions[to];
            reactance=reactance,
            max_capacity=rating,
        )
        PSIP.add_technology!(p_5bus, line)
        PSIP.add_supplemental_attribute!(
            p_5bus,
            line,
            PSIP.ExistingDevices(; existing_devices=[device]),
        )
    end
    set_technology_model!(
        template,
        [l[1] for l in lines],
        PTDF_LINE_TYPE,
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )

    return InvestmentModel(
        template,
        SingleInstanceSolve,
        p_5bus;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
        store_variable_names=true,
    )
end

const TWO_NODE_PLACEMENT = Dict(
    "cheap_thermal" => "Node_1",
    "expensive_thermal" => "Node_1",
    "wind" => "Node_2",
    "demand1" => "Node_1",
    "demand2" => "Node_2",
    "test_storage" => "Node_2",
)

# Two nodes joined by an existing line
function _two_node_model(transport; kwargs...)
    m = _nodal_test_model(
        transport;
        nodes=["Node_1", "Node_2"],
        placement=TWO_NODE_PLACEMENT,
        lines=[("nodal_line", "Node_1", "Node_2", 0.1, "1")],
        kwargs...,
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
    nodal_balance = PSIN.get_expression(nodal, PSIN.EnergyBalance(), PSIP.Portfolio)
    ptdf_balance = PSIN.get_expression(ptdf, PSIN.EnergyBalance(), PSIP.Portfolio)
    @test axes(ptdf_balance) == axes(nodal_balance)

    line_flow = PSIN.get_variable(
        nodal,
        PSIN.FlowActivePowerVariable(),
        PTDF_LINE_TYPE,
        "BasicDispatch",
    )
    line_flow_names = Set(JuMP.name.(line_flow.data))
    for node in axes(nodal_balance, 1), t in axes(nodal_balance, 2)
        nodal_terms = _terms_by_name(nodal_balance[node, t])
        # Under the nodal transport model the line adds its flow to both nodes
        @test count(in(line_flow_names), keys(nodal_terms)) == 1
        injections = filter(((name, _),) -> !in(name, line_flow_names), nodal_terms)
        @test _terms_by_name(ptdf_balance[node, t]) == injections
        @test JuMP.constant(ptdf_balance[node, t]) == JuMP.constant(nodal_balance[node, t])
    end

    # Nodes are not balanced one by one under the PTDF model, and lines have no flow variables
    @test !haskey(
        PSIN.get_constraints(ptdf),
        PSIN.ConstraintKey(NodalBalanceConstraint, PSIP.Portfolio),
    )
    @test !PSIN.has_container_key(
        ptdf,
        PSIN.FlowActivePowerVariable,
        PTDF_LINE_TYPE,
        "BasicDispatch",
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
    @test network.ptdf.axes == (["Node_1", "Node_2"], ["Node_1_Node_2"])
    @test [t.name for t in only(network.merged_corridors).technologies] == ["nodal_line"]
    @test isnothing(
        PSIN.get_network_data(
            PSIN.get_transport_model(PSIN.get_template(_two_node_model(NodalBalanceModel))),
        ),
    )
end

function _solved_objective(m)
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    return JuMP.objective_value(PSIN.get_jump_model(PSIN.get_optimization_container(m)))
end

@testset "PTDF model matches the nodal model on a radial network" begin
    # With a single path between nodes there are no loop flows, so DC power flow adds nothing
    nodal = _two_node_model(NodalBalanceModel)
    ptdf = _two_node_model(NodalPTDFModel)
    @test isapprox(_solved_objective(ptdf), _solved_objective(nodal); rtol=1e-6)
end

# A triangle of existing lines with different reactances: the cheap generator at n1, the
# expensive one at n2, and demand at n2 and n3. The n1-n2 line is limited to 100 MW.
const TRIANGLE_LINES = [
    ("l12", "n1", "n2", 0.1, "1"),
    ("l23", "n2", "n3", 0.2, "4"),
    ("l13", "n1", "n3", 0.3, "3"),
]

function _triangle_model(transport)
    m = _nodal_test_model(
        transport;
        nodes=["n1", "n2", "n3"],
        placement=Dict(
            "cheap_thermal" => "n1",
            "expensive_thermal" => "n2",
            "wind" => "n3",
            "demand1" => "n2",
            "demand2" => "n3",
            "test_storage" => "n2",
        ),
        lines=TRIANGLE_LINES,
        ratings=Dict("1" => 100.0),
        use_slacks=true,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    return m
end

@testset "PTDF model on a meshed network" begin
    m = _triangle_model(NodalPTDFModel)
    container = PSIN.get_optimization_container(m)
    ptdf_objective = _solved_objective(m)

    flow = JuMP.value.(PSIN.get_expression(container, PTDFBranchFlow(), PSIP.Portfolio))
    injection =
        JuMP.value.(PSIN.get_expression(container, PSIN.EnergyBalance(), PSIP.Portfolio))
    # Each corridor runs from its alphabetically first node
    arcs = Dict(
        "n1_n2" => ("n1", "n2", 0.1),
        "n2_n3" => ("n2", "n3", 0.2),
        "n1_n3" => ("n1", "n3", 0.3),
    )
    limits = Dict("n1_n2" => 100.0, "n2_n3" => 796.0, "n1_n3" => 796.0)
    time_steps = axes(flow, 2)
    for t in time_steps
        # Kirchhoff's current law: the injection at each node leaves on its lines
        for node in ("n1", "n2", "n3")
            outflow = sum(
                (from == node ? 1.0 : to == node ? -1.0 : 0.0) * flow[branch, t] for
                (branch, (from, to, _)) in arcs
            )
            @test isapprox(outflow, injection[node, t]; atol=1e-6)
        end
        # Kirchhoff's voltage law around n1 -> n2 -> n3 -> n1 (all lines at 230 kV)
        @test isapprox(
            0.1 * flow["n1_n2", t] + 0.2 * flow["n2_n3", t] - 0.3 * flow["n1_n3", t],
            0.0;
            atol=1e-6,
        )
        for (branch, limit) in limits
            @test abs(flow[branch, t]) <= limit + 1e-6
        end
    end
    # The 100 MW line limits the dispatch
    @test maximum(abs.(flow["n1_n2", :])) ≈ 100.0

    # One island, balanced as a whole
    balance = PSIN.get_constraint(container, IslandBalanceConstraint(), PSIP.Portfolio)
    @test axes(balance, 1) == ["n1"]

    # No demand is left unserved
    for slack in (PSIN.BalanceSlackUp(), PSIN.BalanceSlackDown())
        @test all(
            JuMP.value.(PSIN.get_variable(container, slack, PSIP.Portfolio).data) .<= 1e-6,
        )
    end

    # The transport model ignores Kirchhoff's voltage law and routes the cheap generation
    # around the 100 MW line, so it is cheaper
    nodal_objective = _solved_objective(_triangle_model(NodalBalanceModel))
    @test nodal_objective < ptdf_objective * (1 - 1e-3)
end

@testset "PTDF model rejects lines it does not support yet" begin
    m = _nodal_test_model(
        NodalPTDFModel;
        nodes=["Node_1", "Node_2"],
        placement=TWO_NODE_PLACEMENT,
        lines=[("nodal_line", "Node_1", "Node_2", 0.1, "1")],
    )
    # Discrete candidates are separate unit lines, which are not supported yet
    portfolio = PSIN.get_portfolio(m)
    nodes = Dict(PSIP.get_name(n) => n for n in PSIP.get_regions(PSIP.Node, portfolio))
    candidate = _ptdf_line(
        "new_units",
        nodes["Node_1"],
        nodes["Node_2"];
        unit_size=100.0,
        max_capacity=200.0,
    )
    PSIP.add_technology!(portfolio, candidate)
    set_technology_model!(
        PSIN.get_template(m),
        ["new_units"],
        PTDF_LINE_TYPE,
        IntegerInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true), console_level=Logging.Error) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.FAILED
end

# A ring of existing lines n1-n2-n3-n4 (n1-n2 limited to 100 MW, the others to 2000 MW), two
# candidate diagonals that
# interact, and a candidate to n5, which has no other line. The cheap generator is at n1, the
# expensive one at n2, wind at n5 and demand at n2 and n4.
const RING_LINES = [
    ("r12", "n1", "n2", 0.1, "1"),
    ("r23", "n2", "n3", 0.2, "4"),
    ("r34", "n3", "n4", 0.1, "5"),
    ("r41", "n4", "n1", 0.2, "2"),
]
const RING_CANDIDATES = [
    ("d13", "n1", "n3", 0.1, nothing),
    ("d24", "n2", "n4", 0.1, nothing),
    ("r45", "n4", "n5", 0.1, nothing),
]

function _ring_model(lines; candidate_cost=5000.0)
    m = _nodal_test_model(
        NodalPTDFModel;
        nodes=["n1", "n2", "n3", "n4", "n5"],
        placement=Dict(
            "cheap_thermal" => "n1",
            "expensive_thermal" => "n2",
            "wind" => "n5",
            "demand1" => "n2",
            "demand2" => "n4",
            "test_storage" => "n2",
        ),
        lines=lines,
        ratings=Dict("1" => 100.0, "2" => 2000.0, "4" => 2000.0, "5" => 2000.0),
        use_slacks=true,
        candidate_cost=candidate_cost,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    return m
end

_ring_branch(name, from, to) = isnothing(name) ? join(minmax(from, to), "_") : name

# Checks that the solved flows are a DC power flow of the branches in service: the injection at
# each node leaves on its branches (Kirchhoff's current law), and there are angles that give every
# branch in service its flow (Kirchhoff's voltage law). All lines are at 230 kV, so susceptance is
# proportional to 1 / reactance.
function _test_dc_power_flow(container, lines, in_service)
    flow = JuMP.value.(PSIN.get_expression(container, PTDFBranchFlow(), PSIP.Portfolio))
    injection =
        JuMP.value.(PSIN.get_expression(container, PSIN.EnergyBalance(), PSIP.Portfolio))
    nodes = collect(axes(injection, 1))
    node_ix = Dict(n => i for (i, n) in enumerate(nodes))
    branches = [
        (_ring_branch(isnothing(device) ? name : nothing, from, to), from, to, x) for
        (name, from, to, x, device) in lines
    ]
    # Merged corridors run from the alphabetically first node
    arcs = Dict(
        branch => (isnothing(device) ? (from, to) : minmax(from, to)) for
        ((branch, from, to, _), (_, _, _, _, device)) in zip(branches, lines)
    )
    for t in axes(flow, 2)
        for node in nodes
            outflow = sum(
                (arcs[b][1] == node ? 1.0 : arcs[b][2] == node ? -1.0 : 0.0) * flow[b, t] for (b, _, _, _) in branches
            )
            @test isapprox(outflow, injection[node, t]; atol=1e-5)
        end
        served = [(b, x) for (b, _, _, x) in branches if b in in_service]
        A = zeros(length(served), length(nodes))
        for (row, (b, _)) in enumerate(served)
            A[row, node_ix[arcs[b][1]]] = 1.0
            A[row, node_ix[arcs[b][2]]] = -1.0
        end
        angle_differences = [flow[b, t] * x for (b, x) in served]
        theta = A \ angle_differences
        @test isapprox(A * theta, angle_differences; atol=1e-5)
    end
    return flow
end

@testset "Unbuilt new corridors have no effect on the network" begin
    ring = _ring_model(RING_LINES)
    ring_objective = _solved_objective(ring)
    # The candidates cost too much to be built
    with_candidates = _ring_model([RING_LINES; RING_CANDIDATES]; candidate_cost=1e12)
    @test isapprox(_solved_objective(with_candidates), ring_objective; rtol=1e-6)

    container = PSIN.get_optimization_container(with_candidates)
    # Nothing is built. The built binary of a corridor with no capacity may still be 1, since a
    # corridor without capacity carries no flow either way.
    capacity = PSIN.get_expression(
        container,
        PSIN.CumulativeCapacity(),
        PTDF_LINE_TYPE,
        "ContinuousInvestment",
    )
    for candidate in ("d13", "d24", "r45")
        @test all(JuMP.value.(capacity[candidate, :]) .<= 1e-6)
    end
    ring_names = ["n1_n2", "n2_n3", "n3_n4", "n1_n4"]
    flow = _test_dc_power_flow(container, [RING_LINES; RING_CANDIDATES], ring_names)
    for candidate in ("d13", "d24", "r45")
        @test all(abs.(flow[candidate, :]) .<= 1e-6)
    end
    ring_flow =
        JuMP.value.(
            PSIN.get_expression(
                PSIN.get_optimization_container(ring),
                PTDFBranchFlow(),
                PSIP.Portfolio,
            ),
        )
    for name in ring_names
        @test isapprox(flow[name, :].data, ring_flow[name, :].data; atol=1e-4)
    end
end

@testset "Built new corridors carry their PTDF flow" begin
    m = _ring_model([RING_LINES; RING_CANDIDATES]; candidate_cost=1.0)
    _solved_objective(m)
    container = PSIN.get_optimization_container(m)
    built =
        JuMP.value.(
            PSIN.get_variable(container, NewCorridorBuiltVariable(), PSIP.Portfolio),
        )
    # Cheap candidates relieve the 100 MW line and connect the wind at n5
    @test built["r45", 1] > 0.5
    @test any(built[c, 1] > 0.5 for c in ("d13", "d24"))
    in_service = [
        ["n1_n2", "n2_n3", "n3_n4", "n1_n4"]
        [c for c in ("d13", "d24", "r45") if built[c, 1] > 0.5]
    ]
    _test_dc_power_flow(container, [RING_LINES; RING_CANDIDATES], in_service)
    transactions =
        JuMP.value.(
            PSIN.get_variable(container, VirtualTransactionVariable(), PSIP.Portfolio),
        )
    for c in ("d13", "d24", "r45")
        built[c, 1] > 0.5 || continue
        @test all(abs.(transactions[c, :]) .<= 1e-6)
    end
end
