const PTDF_TECHNOLOGIES = (
    (PSIP.SupplyTechnology{PSY.ThermalStandard}, "cheap_thermal", ContinuousInvestment),
    (PSIP.SupplyTechnology{PSY.ThermalStandard}, "expensive_thermal", ContinuousInvestment),
    (PSIP.SupplyTechnology{PSY.RenewableDispatch}, "wind", ContinuousInvestment),
    (PSIP.ProjectedDemand{PSY.PowerLoad}, "demand1", StaticLoadInvestment),
    (PSIP.ProjectedDemand{PSY.PowerLoad}, "demand2", StaticLoadInvestment),
)

const PTDF_LINE_TYPE = PSIP.NodalACTransportTechnology{PSY.Line}
const HVDC_TYPE = PSIP.NodalHVDCTransportTechnology{PSY.TwoTerminalGenericHVDCLine}

const TEST_FINANCIAL_DATA = PSIP.TechnologyFinancialData(;
    capital_recovery_period=30,
    technology_base_year=2025,
    debt_fraction=0.6,
    debt_rate=0.04,
    return_on_equity=0.10,
    tax_rate=0.21,
)

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
        financial_data=TEST_FINANCIAL_DATA,
    )
end

# 2-zone test portfolio on nodes. `lines` are (name, from, to, reactance, existing line of
# the base system); lines without an existing line are candidates of up to 1000 MW.
# `discrete_lines` are (name, from, to, reactance, formulation, unit size, capacity limit),
# and `hvdc_lines` are (name, from, to, operations formulation, line loss).
_operations_formulation(::Type{<:PSIP.Technology}, demand_formulation) = BasicDispatch
_operations_formulation(::Type{<:PSIP.ProjectedDemand}, demand_formulation) =
    demand_formulation

function _nodal_test_model(
    transport;
    nodes,
    placement,
    lines,
    ratings=Dict{String, Float64}(),
    demand_formulation=BasicDispatch,
    candidate_cost=5000.0,
    candidate_costs=Dict{String, Float64}(),
    discrete_lines=[],
    hvdc_lines=[],
    attributes=Dict{String, Any}(),
    algorithm=SingleInstanceSolve,
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
        TransportModel(transport; attributes=attributes),
    )
    regions = Dict(
        n => PSIP.Node(;
            name=n,
            id=100 + i,
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
            _operations_formulation(type, demand_formulation),
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
                capital_cost=get(candidate_costs, name, candidate_cost),
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
            PSIP.ExistingDevices(; id=1, existing_devices=[device]),
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
    for (name, from, to, reactance, formulation, unit_size, max_capacity) in discrete_lines
        line = _ptdf_line(
            name,
            regions[from],
            regions[to];
            reactance=reactance,
            unit_size=unit_size,
            max_capacity=max_capacity,
            capital_cost=candidate_cost,
        )
        PSIP.add_technology!(p_5bus, line)
        set_technology_model!(
            template,
            [name],
            PTDF_LINE_TYPE,
            formulation,
            BasicDispatch,
            BasicDispatchFeasibility,
        )
    end
    for (name, from, to, operation, line_loss) in hvdc_lines
        hvdc = HVDC_TYPE(;
            name=name,
            start_node=regions[from],
            end_node=regions[to],
            capacity_limits=(min=0, max=1000),
            capital_costs=PSIP.CapitalCost(LinearCurve(candidate_cost), 0.0),
            line_loss=line_loss,
            available=true,
            power_systems_type="TwoTerminalGenericHVDCLine",
            id=1,
            financial_data=TEST_FINANCIAL_DATA,
        )
        PSIP.add_technology!(p_5bus, hvdc)
        set_technology_model!(
            template,
            [name],
            HVDC_TYPE,
            ContinuousInvestment,
            operation,
            BasicDispatchFeasibility,
        )
    end

    return InvestmentModel(
        template,
        algorithm,
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

# Coefficients of an expression by variable name
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
        @test count(in(line_flow_names), keys(nodal_terms)) == 1
        injections = filter(((name, _),) -> !in(name, line_flow_names), nodal_terms)
        @test _terms_by_name(ptdf_balance[node, t]) == injections
        @test JuMP.constant(ptdf_balance[node, t]) == JuMP.constant(nodal_balance[node, t])
    end

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

# Four nodes A (reference) to D; lines are (name, from, to, formulation, keywords)
function _ptdf_network_data(lines; tol=0.0)
    portfolio, op_days = test_2_zone_portfolio()
    sys = build_system(PSITestSystems, "c_sys5_re")
    set_units_base_system!(sys, "NATURAL_UNITS")
    PSIP.set_base_system!(portfolio, sys)
    nodes = Dict(
        n => PSIP.Node(;
            name=n,
            id=100 + i,
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
                PSIP.ExistingDevices(; id=1, existing_devices=["1"]),
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

    # The merged corridor has the susceptance of the existing line only
    corridor = only(network.merged_corridors)
    @test corridor.name == "A_B"
    @test corridor.arc == ("A", "B")
    @test corridor.susceptance ≈ b
    @test corridor.fixed_capacity == 0.0
    @test sort([t.name for t in corridor.expandable_lines]) == ["ab_existing", "ab_new"]

    new_corridor = only(network.new_corridors)
    @test new_corridor.name == "bc_new"
    @test new_corridor.arc == ("B", "C")

    # The binary line has one unit although its capacity limit allows more
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
    # The unit lines run B to A
    for node in ptdf.axes[1], unit in ("ba_units_unit_1", "ba_units_unit_3")
        @test ptdf[unit, node] ≈ -ptdf["A_B", node]
    end
end

@testset "PTDF network branch checks" begin
    @test_throws ErrorException _ptdf_network_data([
        ("ab", "A", "B", IntegerInvestment, (max_capacity=1e8,)),
    ])
    # PSIP rejects a non-positive unit size when the line is added
    @test_logs (:error, r"unit size") match_mode = :any @test_throws IS.InvalidValue _ptdf_network_data([
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
    corridor = only(network.merged_corridors)
    @test isempty(corridor.expandable_lines)
    @test [t.name for (t, _) in corridor.fixed_lines] == ["nodal_line"]
    @test corridor.fixed_capacity > 0.0
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
    nodal = _two_node_model(NodalBalanceModel)
    ptdf = _two_node_model(NodalPTDFModel)
    @test isapprox(_solved_objective(ptdf), _solved_objective(nodal); rtol=1e-6)
end

@testset "HVDC links" begin
    loss = LinearCurve(0.02, 0.01)
    objectives = Dict()
    for operation in (BasicDispatch, BasicDispatchWithLosses),
        transport in (NodalBalanceModel, NodalPTDFModel)

        m = _two_node_model(
            transport;
            ratings=Dict("1" => 100.0),
            hvdc_lines=[("hvdc", "Node_1", "Node_2", operation, loss)],
        )
        objectives[operation, transport] = _solved_objective(m)
        operation == BasicDispatchWithLosses || continue
        container = PSIN.get_optimization_container(m)
        meta = "BasicDispatchWithLosses"
        from_to =
            PSIN.get_variable(container, FlowActivePowerFromToVariable(), HVDC_TYPE, meta)
        to_from =
            PSIN.get_variable(container, FlowActivePowerToFromVariable(), HVDC_TYPE, meta)
        build = PSIN.get_variable(
            container,
            PSIN.BuildCapacity(),
            HVDC_TYPE,
            "ContinuousInvestment",
        )
        balance = PSIN.get_expression(container, PSIN.EnergyBalance(), PSIP.Portfolio)
        for (node, sent, received) in
            (("Node_1", from_to, to_from), ("Node_2", to_from, from_to))
            @test JuMP.coefficient(balance[node, 1], sent["hvdc", 1]) == -1.0
            @test JuMP.coefficient(balance[node, 1], received["hvdc", 1]) ≈ 0.98
            # Half of the constant loss per MW of capacity at each end
            @test JuMP.coefficient(balance[node, 1], build["hvdc", 1]) ≈ -0.005
        end
    end
    for operation in (BasicDispatch, BasicDispatchWithLosses)
        @test isapprox(
            objectives[operation, NodalPTDFModel],
            objectives[operation, NodalBalanceModel];
            rtol=1e-6,
        )
    end
    @test objectives[BasicDispatchWithLosses, NodalBalanceModel] >
          objectives[BasicDispatch, NodalBalanceModel]
end

# A triangle of existing lines with different reactances: the cheap generator at n1, the
# expensive one at n2, and demand at n2 and n3. The n1-n2 line is limited to 100 MW.
const TRIANGLE_LINES = [
    ("l12", "n1", "n2", 0.1, "1"),
    ("l23", "n2", "n3", 0.2, "4"),
    ("l13", "n1", "n3", 0.3, "3"),
]

function _triangle_model(
    transport;
    attributes=Dict{String, Any}(),
    algorithm=SingleInstanceSolve,
)
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
        demand_formulation=UnservedDemandDispatch,
        attributes=attributes,
        algorithm=algorithm,
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
    arcs = Dict(
        "n1_n2" => ("n1", "n2", 0.1),
        "n2_n3" => ("n2", "n3", 0.2),
        "n1_n3" => ("n1", "n3", 0.3),
    )
    limits = Dict("n1_n2" => 100.0, "n2_n3" => 796.0, "n1_n3" => 796.0)
    time_steps = axes(flow, 2)
    for t in time_steps
        # KCL
        for node in ("n1", "n2", "n3")
            outflow = sum(
                (from == node ? 1.0 : to == node ? -1.0 : 0.0) * flow[branch, t] for
                (branch, (from, to, _)) in arcs
            )
            @test isapprox(outflow, injection[node, t]; atol=1e-6)
        end
        # KVL around n1 -> n2 -> n3 -> n1
        @test isapprox(
            0.1 * flow["n1_n2", t] + 0.2 * flow["n2_n3", t] - 0.3 * flow["n1_n3", t],
            0.0;
            atol=1e-6,
        )
        for (branch, limit) in limits
            @test abs(flow[branch, t]) <= limit + 1e-6
        end
    end
    @test maximum(abs.(flow["n1_n2", :])) ≈ 100.0
    reported = PSIN.get_aux_variables(container)[PSIN.AuxVarKey(BranchFlow, PSIP.Portfolio)]
    @test isapprox(reported[axes(flow, 1), :].data, flow.data; atol=1e-6)

    balance = PSIN.get_constraint(container, IslandBalanceConstraint(), PSIP.Portfolio)
    @test axes(balance, 1) == ["n1"]

    unserved = PSIN.get_variable(
        container,
        UnservedDemandVariable(),
        PSIP.ProjectedDemand{PSY.PowerLoad},
        "UnservedDemandDispatch",
    )
    @test all(JuMP.value.(unserved.data) .<= 1e-6)

    # The transport model ignores KVL, so it is cheaper
    nodal_objective = _solved_objective(_triangle_model(NodalBalanceModel))
    @test nodal_objective < ptdf_objective * (1 - 1e-3)
end

# A ring of existing lines n1-n2-n3-n4 (n1-n2 limited to 100 MW, the others to 2000 MW), two
# candidate diagonals that interact, and a candidate to n5, which has no other line. The
# cheap generator is at n1, the expensive one at n2, wind at n5 and demand at n2 and n4.
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

function _ring_model(
    lines;
    candidate_cost=5000.0,
    candidate_costs=Dict{String, Float64}(),
    discrete_lines=[],
    attributes=Dict{String, Any}(),
    algorithm=SingleInstanceSolve,
)
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
        demand_formulation=UnservedDemandDispatch,
        candidate_cost=candidate_cost,
        candidate_costs=candidate_costs,
        discrete_lines=discrete_lines,
        attributes=attributes,
        algorithm=algorithm,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    return m
end

# Expected PTDF branches (name, arc, reactance) of the lines
function _ptdf_branches(lines, discrete_lines=[])
    branches = Tuple{String, Tuple{String, String}, Float64}[]
    for (name, from, to, x, device) in lines
        if isnothing(device)
            push!(branches, (name, (from, to), x))
        else
            push!(branches, (join(minmax(from, to), "_"), minmax(from, to), x))
        end
    end
    for (name, from, to, x, formulation, unit_size, max_capacity) in discrete_lines
        units = formulation == BinaryInvestment ? 1 : floor(Int, max_capacity / unit_size)
        for unit in 1:units
            push!(branches, ("$(name)_unit_$(unit)", (from, to), x))
        end
    end
    return branches
end

# Checks KCL and KVL for the branches in service (all lines at 230 kV), and that the other
# branches carry no flow. `in_service` are always in service, and `candidates` when their
# built binary is 1 in the investment period of the time step.
function _test_dc_power_flow(container, branches, in_service; candidates=String[])
    flow = PSIN.get_aux_variables(container)[PSIN.AuxVarKey(BranchFlow, PSIP.Portfolio)]
    injection =
        JuMP.value.(PSIN.get_expression(container, PSIN.EnergyBalance(), PSIP.Portfolio))
    built = if isempty(candidates)
        nothing
    else
        JuMP.value.(PSIN.get_variable(container, BranchBuiltVariable(), PSIP.Portfolio))
    end
    time_mapping = PSIN.get_time_mapping(container)
    investment_period = Dict(
        t => PSIN.get_inverse_invest_mapping(time_mapping)[op_ix] for
        (op_ix, slices) in pairs(PSIN.get_consecutive_slices(time_mapping)) for
        t in slices
    )
    nodes = collect(axes(injection, 1))
    node_ix = Dict(n => i for (i, n) in enumerate(nodes))
    for t in axes(flow, 2)
        for node in nodes
            outflow = sum(
                (from == node ? 1.0 : to == node ? -1.0 : 0.0) * flow[b, t] for
                (b, (from, to), _) in branches
            )
            @test isapprox(outflow, injection[node, t]; atol=1e-5)
        end
        serves(b) =
            b in in_service || (b in candidates && built[b, investment_period[t]] > 0.5)
        served = [(b, arc, x) for (b, arc, x) in branches if serves(b)]
        for (b, _, _) in branches
            serves(b) || @test abs(flow[b, t]) <= 1e-6
        end
        A = zeros(length(served), length(nodes))
        for (row, (_, (from, to), _)) in enumerate(served)
            A[row, node_ix[from]] = 1.0
            A[row, node_ix[to]] = -1.0
        end
        angle_differences = [flow[b, t] * x for (b, _, x) in served]
        # The first node touched is the angle reference
        touched = findall(j -> any(!iszero, A[:, j]), axes(A, 2))
        reduced = A[:, touched[2:end]]
        theta = reduced \ angle_differences
        @test isapprox(reduced * theta, angle_differences; atol=1e-5)
    end
    return flow
end

@testset "Unbuilt new corridors have no effect on the network" begin
    ring = _ring_model(RING_LINES)
    ring_objective = _solved_objective(ring)
    with_candidates = _ring_model([RING_LINES; RING_CANDIDATES]; candidate_cost=1e12)
    @test isapprox(_solved_objective(with_candidates), ring_objective; rtol=1e-6)

    container = PSIN.get_optimization_container(with_candidates)
    # The built binary of a corridor without capacity may still be 1
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
    flow = _test_dc_power_flow(
        container,
        _ptdf_branches([RING_LINES; RING_CANDIDATES]),
        ring_names,
    )
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
        JuMP.value.(PSIN.get_variable(container, BranchBuiltVariable(), PSIP.Portfolio),)
    @test built["r45", 1] > 0.5
    @test any(built[c, 1] > 0.5 for c in ("d13", "d24"))
    _test_dc_power_flow(
        container,
        _ptdf_branches([RING_LINES; RING_CANDIDATES]),
        ["n1_n2", "n2_n3", "n3_n4", "n1_n4"];
        candidates=["d13", "d24", "r45"],
    )
    transactions =
        JuMP.value.(
            PSIN.get_variable(container, VirtualTransactionVariable(), PSIP.Portfolio),
        )
    for c in ("d13", "d24", "r45")
        built[c, 1] > 0.5 || continue
        @test all(abs.(transactions[c, :]) .<= 1e-6)
    end
end

# Two nodes joined by an existing 100 MW line of reactance 0.1 and an integer candidate of
# two 100 MW units of reactance 0.2. The cheap generator is at Node_1 and the expensive one
# and most of the demand at Node_2, so the corridor is congested.
@testset "Unit lines share the corridor flow by susceptance" begin
    discrete_lines = [("units", "Node_1", "Node_2", 0.2, IntegerInvestment, 100.0, 200.0)]
    m = _nodal_test_model(
        NodalPTDFModel;
        nodes=["Node_1", "Node_2"],
        placement=Dict(
            "cheap_thermal" => "Node_1",
            "expensive_thermal" => "Node_2",
            "wind" => "Node_2",
            "demand1" => "Node_1",
            "demand2" => "Node_2",
            "test_storage" => "Node_2",
        ),
        lines=[("existing", "Node_1", "Node_2", 0.1, "1")],
        ratings=Dict("1" => 100.0),
        candidate_cost=1.0,
        discrete_lines=discrete_lines,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    _solved_objective(m)
    container = PSIN.get_optimization_container(m)
    built = JuMP.value.(PSIN.get_variable(container, BranchBuiltVariable(), PSIP.Portfolio))
    build =
        JuMP.value.(
            PSIN.get_variable(
                container,
                PSIN.BuildCapacity(),
                PTDF_LINE_TYPE,
                "IntegerInvestment",
            ),
        )
    @test sum(built[:, 1]) ≈ sum(build["units", 1]) ≈ 2.0
    flow = _test_dc_power_flow(
        container,
        _ptdf_branches([("existing", "Node_1", "Node_2", 0.1, "1")], discrete_lines),
        ["Node_1_Node_2"];
        candidates=["units_unit_1", "units_unit_2"],
    )
    for t in axes(flow, 2)
        # Each unit has half the susceptance of the existing line
        for unit in ("units_unit_1", "units_unit_2")
            @test isapprox(flow[unit, t], 0.5 * flow["Node_1_Node_2", t]; atol=1e-6)
        end
    end
    # The existing line reaches its limit first: at most 200 MW, not 300
    transfer = [
        flow["Node_1_Node_2", t] + flow["units_unit_1", t] + flow["units_unit_2", t] for
        t in axes(flow, 2)
    ]
    @test maximum(transfer) ≈ 200.0
end

const RING_DISCRETE = [
    ("d13", "n1", "n3", 0.1, IntegerInvestment, 500.0, 1000.0),
    ("d24", "n2", "n4", 0.1, BinaryInvestment, 1000.0, 1000.0),
]

@testset "Unbuilt unit lines have no effect on the network" begin
    ring_objective = _solved_objective(_ring_model(RING_LINES))
    m = _ring_model(RING_LINES; candidate_cost=1e12, discrete_lines=RING_DISCRETE)
    @test isapprox(_solved_objective(m), ring_objective; rtol=1e-6)
    container = PSIN.get_optimization_container(m)
    built = JuMP.value.(PSIN.get_variable(container, BranchBuiltVariable(), PSIP.Portfolio))
    @test all(built.data .< 0.5)
    flow = _test_dc_power_flow(
        container,
        _ptdf_branches(RING_LINES, RING_DISCRETE),
        ["n1_n2", "n2_n3", "n3_n4", "n1_n4"],
    )
    for unit in ("d13_unit_1", "d13_unit_2", "d24_unit_1")
        @test all(abs.(flow[unit, :]) .<= 1e-6)
    end
end

@testset "Built unit lines carry their PTDF flow" begin
    m = _ring_model(RING_LINES; candidate_cost=1.0, discrete_lines=RING_DISCRETE)
    _solved_objective(m)
    container = PSIN.get_optimization_container(m)
    built = JuMP.value.(PSIN.get_variable(container, BranchBuiltVariable(), PSIP.Portfolio))
    @test any(built.data .> 0.5)
    _test_dc_power_flow(
        container,
        _ptdf_branches(RING_LINES, RING_DISCRETE),
        ["n1_n2", "n2_n3", "n3_n4", "n1_n4"];
        candidates=["d13_unit_1", "d13_unit_2", "d24_unit_1"],
    )
end

# An existing 800 MW line and an integer candidate of two 1000 MW units with twice its
# susceptance: one unit is enough for the 2030 transfers and both are needed in 2035
@testset "Integer units are built in order" begin
    discrete_lines =
        [("units", "Node_1", "Node_2", 0.05, IntegerInvestment, 1000.0, 2000.0)]
    m = _nodal_test_model(
        NodalPTDFModel;
        nodes=["Node_1", "Node_2"],
        placement=Dict(
            "cheap_thermal" => "Node_1",
            "expensive_thermal" => "Node_2",
            "wind" => "Node_2",
            "demand1" => "Node_1",
            "demand2" => "Node_2",
            "test_storage" => "Node_2",
        ),
        lines=[("existing", "Node_1", "Node_2", 0.1, "1")],
        ratings=Dict("1" => 800.0),
        candidate_cost=1.0,
        discrete_lines=discrete_lines,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    _solved_objective(m)
    container = PSIN.get_optimization_container(m)
    built = JuMP.value.(PSIN.get_variable(container, BranchBuiltVariable(), PSIP.Portfolio))
    @test built["units_unit_1", :].data ≈ [1.0, 1.0] atol = 1e-6
    @test built["units_unit_2", :].data ≈ [0.0, 1.0] atol = 1e-6
    _test_dc_power_flow(
        container,
        _ptdf_branches([("existing", "Node_1", "Node_2", 0.1, "1")], discrete_lines),
        ["Node_1_Node_2"];
        candidates=["units_unit_1", "units_unit_2"],
    )
end

# Two candidates to n5, which has no existing line: the unbuilt one must cancel the flow of
# the built one, so its big-M cannot assume the corridor carries nothing
@testset "Candidates to a node without existing lines" begin
    r45 = ("r45", "n4", "n5", 0.1, nothing)
    r35 = ("r35", "n3", "n5", 0.2, nothing)
    expensive = Dict("r35" => 1e12)
    only_r45 = _solved_objective(_ring_model([RING_LINES; [r45]]; candidate_cost=1.0))
    m = _ring_model([RING_LINES; [r45, r35]]; candidate_cost=1.0, candidate_costs=expensive)
    @test isapprox(_solved_objective(m), only_r45; rtol=1e-6)
    container = PSIN.get_optimization_container(m)
    built = JuMP.value.(PSIN.get_variable(container, BranchBuiltVariable(), PSIP.Portfolio))
    @test built["r45", 1] > 0.5
    capacity = PSIN.get_expression(
        container,
        PSIN.CumulativeCapacity(),
        PTDF_LINE_TYPE,
        "ContinuousInvestment",
    )
    @test all(JuMP.value.(capacity["r35", :]) .<= 1e-6)
    _test_dc_power_flow(
        container,
        _ptdf_branches([RING_LINES; [r45, r35]]),
        ["n1_n2", "n2_n3", "n3_n4", "n1_n4"];
        candidates=["r45", "r35"],
    )
end

@testset "PTDF cutoff" begin
    tol = 0.4
    m = _triangle_model(NodalPTDFModel; attributes=Dict{String, Any}("tol" => tol))
    container = PSIN.get_optimization_container(m)
    network = PSIN.get_network_data(PSIN.get_transport_model(PSIN.get_template(m)))
    ptdf = network.ptdf
    @test any(0.0 < abs(x) <= tol for x in ptdf.data)
    flow = PSIN.get_expression(container, PTDFBranchFlow(), PSIP.Portfolio)
    dispatch = PSIN.get_variable(
        container,
        PSIN.ActivePowerVariable(),
        PSIP.SupplyTechnology{PSY.ThermalStandard},
        "BasicDispatch",
    )
    for branch in ptdf.axes[2],
        (generator, node) in (("cheap_thermal", "n1"), ("expensive_thermal", "n2"))

        factor = ptdf[branch, node]
        expected = abs(factor) > tol ? factor : 0.0
        @test JuMP.coefficient(flow[branch, 1], dispatch[generator, 1]) ≈ expected
    end
    _solved_objective(m)
    # Reported flows use the whole PTDF
    model_flow = JuMP.value.(flow)
    reported = PSIN.get_aux_variables(container)[PSIN.AuxVarKey(BranchFlow, PSIP.Portfolio)]
    @test maximum(abs.(model_flow.data .- reported[axes(model_flow, 1), :].data)) > 1.0
end

@testset "Iterative monitoring" begin
    full = _triangle_model(NodalPTDFModel)
    full_objective = _solved_objective(full)
    full_flow =
        PSIN.get_aux_variables(PSIN.get_optimization_container(full))[PSIN.AuxVarKey(
            BranchFlow,
            PSIP.Portfolio,
        )]
    for flow_variables in (false, true)
        m = _triangle_model(
            NodalPTDFModel;
            attributes=Dict{String, Any}("flow_variables" => flow_variables),
            algorithm=IterativeMonitoring,
        )
        @test isempty(PSIN.get_monitored_corridors(m))
        @test isapprox(_solved_objective(m), full_objective; rtol=1e-6)
        log = get_monitoring_log(m)
        @test size(log, 1) >= 2
        @test log.added[1] > 0
        @test last(log.added) == 0
        @test last(log.overloaded) == 0
        monitored = PSIN.get_monitored_corridors(m)
        @test !isempty(monitored)
        container = PSIN.get_optimization_container(m)
        @test sort(
            axes(PSIN.get_expression(container, PTDFBranchFlow(), PSIP.Portfolio), 1),
        ) == monitored
        limits =
            PSIN.get_constraint(container, FlowRateConstraint(), PSIP.Portfolio, "range")
        @test sort(axes(limits, 1)) == monitored
        flow = PSIN.get_aux_variables(container)[PSIN.AuxVarKey(BranchFlow, PSIP.Portfolio)]
        @test isapprox(flow.data, full_flow.data; atol=1e-3)
    end
    m = _triangle_model(
        NodalPTDFModel;
        attributes=Dict{String, Any}("max_iterations" => 0),
        algorithm=IterativeMonitoring,
    )
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    @test size(get_monitoring_log(m), 1) == 1
    @test last(get_monitoring_log(m).overloaded) > 0
    transport = _nodal_test_model(
        NodalBalanceModel;
        nodes=["Node_1", "Node_2"],
        placement=TWO_NODE_PLACEMENT,
        lines=[("nodal_line", "Node_1", "Node_2", 0.1, "1")],
        algorithm=IterativeMonitoring,
    )
    @test build!(
        transport;
        output_dir=mktempdir(; cleanup=true),
        console_level=Logging.AboveMaxLevel,
    ) == IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.FAILED
end

@testset "Iterative monitoring of a MIP" begin
    lines = [RING_LINES; RING_CANDIDATES]
    objective = _solved_objective(_ring_model(lines; candidate_cost=1.0))
    for (attributes, first_stage) in (
        (Dict{String, Any}(), "relaxed"),
        (Dict{String, Any}("relaxed_screening" => false), "final"),
        (Dict{String, Any}("screening_mip_gap" => 0.05), "relaxed"),
        (
            Dict{String, Any}("relaxed_screening" => false, "screening_mip_gap" => 0.05),
            "screening gap",
        ),
        # The last solve is a final one even when the rounds run out while screening
        (Dict{String, Any}("max_iterations" => 0), "relaxed"),
    )
        m = _ring_model(
            lines;
            candidate_cost=1.0,
            attributes=attributes,
            algorithm=IterativeMonitoring,
        )
        objective_m = _solved_objective(m)
        log = get_monitoring_log(m)
        @test last(log.stage) == "final"
        @test first(log.stage) == first_stage
        haskey(attributes, "max_iterations") ||
            @test isapprox(objective_m, objective; rtol=1e-4)
        @test PSIN.is_milp(PSIN.get_optimization_container(m))
    end
end

@testset "Flow variables" begin
    expressions = _triangle_model(NodalPTDFModel)
    objective = _solved_objective(expressions)
    m = _triangle_model(
        NodalPTDFModel;
        attributes=Dict{String, Any}("flow_variables" => true),
    )
    container = PSIN.get_optimization_container(m)
    variable = PSIN.get_variable(container, FlowActivePowerVariable(), PSIP.Portfolio)
    @test sort(axes(variable, 1)) == ["n1_n2", "n1_n3", "n2_n3"]
    @test !isempty(PSIN.get_constraint(container, NetworkFlowConstraint(), PSIP.Portfolio))
    limits = PSIN.get_constraint(container, FlowRateConstraint(), PSIP.Portfolio, "range")
    @test length(JuMP.constraint_object(limits["n1_n2", 1]).func.terms) == 1
    @test isapprox(_solved_objective(m), objective; rtol=1e-6)
    flow = PSIN.get_aux_variables(container)[PSIN.AuxVarKey(BranchFlow, PSIP.Portfolio)]
    @test isapprox(JuMP.value.(variable).data, flow[axes(variable, 1), :].data; atol=1e-4)
end

@testset "Unmonitored corridors" begin
    monitored = _triangle_model(NodalPTDFModel)
    monitored_objective = _solved_objective(monitored)
    # Leaves out the n1-n2 corridor
    m = _triangle_model(
        NodalPTDFModel;
        attributes=Dict{String, Any}("monitored" => ["l23", "l13"]),
    )
    container = PSIN.get_optimization_container(m)
    limits = PSIN.get_constraint(container, FlowRateConstraint(), PSIP.Portfolio, "range")
    @test sort(axes(limits, 1)) == ["n1_n3", "n2_n3"]
    @test _solved_objective(m) < monitored_objective * (1 - 1e-3)
    @test sort(axes(PSIN.get_expression(container, PTDFBranchFlow(), PSIP.Portfolio), 1)) ==
          ["n1_n3", "n2_n3"]
    flow = PSIN.get_aux_variables(container)[PSIN.AuxVarKey(BranchFlow, PSIP.Portfolio)]
    @test maximum(abs.(flow["n1_n2", :])) > 100.0 + 1e-3
    results = PSIN.read_aux_variable(m, PSIN.AuxVarKey(BranchFlow, PSIP.Portfolio))
    @test sort(unique(results.name)) == ["n1_n2", "n1_n3", "n2_n3"]
    _test_dc_power_flow(
        container,
        _ptdf_branches(TRIANGLE_LINES),
        ["n1_n2", "n2_n3", "n1_n3"],
    )

    unknown = _nodal_test_model(
        NodalPTDFModel;
        nodes=["Node_1", "Node_2"],
        placement=TWO_NODE_PLACEMENT,
        lines=[("nodal_line", "Node_1", "Node_2", 0.1, "1")],
        attributes=Dict{String, Any}("monitored" => ["not_a_line"]),
    )
    @test build!(
        unknown;
        output_dir=mktempdir(; cleanup=true),
        console_level=Logging.AboveMaxLevel,
    ) == IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.FAILED
end

# A congested corridor with an existing line, a continuous candidate running the other way
# and an integer candidate
@testset "Line flows in a merged corridor" begin
    lines = [
        ("existing", "Node_1", "Node_2", 0.1, "1"),
        ("expansion", "Node_2", "Node_1", 0.1, nothing),
    ]
    discrete_lines = [("units", "Node_1", "Node_2", 0.2, IntegerInvestment, 100.0, 200.0)]
    m = _nodal_test_model(
        NodalPTDFModel;
        nodes=["Node_1", "Node_2"],
        placement=Dict(
            "cheap_thermal" => "Node_1",
            "expensive_thermal" => "Node_2",
            "wind" => "Node_2",
            "demand1" => "Node_1",
            "demand2" => "Node_2",
            "test_storage" => "Node_2",
        ),
        lines=lines,
        ratings=Dict("1" => 100.0),
        candidate_cost=1.0,
        discrete_lines=discrete_lines,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    _solved_objective(m)
    container = PSIN.get_optimization_container(m)
    line_flow = PSIN.get_aux_variables(container)[PSIN.AuxVarKey(LineFlow, PSIP.Portfolio)]
    @test sort(axes(line_flow, 1)) == ["existing", "expansion", "units"]
    flow = JuMP.value.(PSIN.get_expression(container, PTDFBranchFlow(), PSIP.Portfolio))
    capacity =
        JuMP.value.(
            PSIN.get_expression(
                container,
                PSIN.CumulativeCapacity(),
                PTDF_LINE_TYPE,
                "ContinuousInvestment",
            ),
        )
    @test capacity["expansion", 1] > 1.0
    time_mapping = PSIN.get_time_mapping(container)
    period = Dict(
        t => PSIN.get_inverse_invest_mapping(time_mapping)[op_ix] for
        (op_ix, slices) in enumerate(PSIN.get_consecutive_slices(time_mapping)) for
        t in slices
    )
    for t in axes(flow, 2)
        # The candidate built the other way has the opposite sign
        @test line_flow["existing", t] - line_flow["expansion", t] ≈
              flow["Node_1_Node_2", t]
        @test line_flow["existing", t] / capacity["existing", period[t]] ≈
              -line_flow["expansion", t] / capacity["expansion", period[t]]
        @test line_flow["units", t] ≈ flow["units_unit_1", t] + flow["units_unit_2", t]
    end
    results = PSIN.read_aux_variable(m, PSIN.AuxVarKey(LineFlow, PSIP.Portfolio))
    @test sort(unique(results.name)) == ["existing", "expansion", "units"]
end

# The area of the reserve margin is n3, the node of demand2: l13 and l23 enter it and l12 is
# fully outside
@testset "Capacity reserve margin with PTDF flows" begin
    m = _nodal_test_model(
        NodalPTDFModel;
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
        demand_formulation=UnservedDemandDispatch,
        attributes=Dict{String, Any}("monitored" => String[]),
    )
    p = PSIN.get_portfolio(m)
    requirement = PSIP.CapacityReserveMargin(;
        name="reserve_margin",
        id=1,
        available=true,
        target_year=2030,
        capacity_reserve_fraction=0.3,
    )
    PSIP.add_requirement!(p, requirement)
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    demand_type = PSIP.ProjectedDemand{PSY.PowerLoad}
    for (type, name) in (
        (thermal_type, "cheap_thermal"),
        (demand_type, "demand2"),
        (PTDF_LINE_TYPE, "l12"),
        (PTDF_LINE_TYPE, "l13"),
        (PTDF_LINE_TYPE, "l23"),
    )
        PSIP.set_requirements!(PSIP.get_technology(type, p, name), [requirement])
    end
    @test_logs (:warn, r"l12 is fully outside the area") PSIN._boundary_lines(
        p,
        requirement;
        warn=true,
    )
    set_requirement_model!(
        PSIN.get_template(m),
        ["reserve_margin"],
        PSIP.CapacityReserveMargin,
        RequirementCapacityReserveMargin,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    # The corridors entering the area are monitored so that their flows are in the model
    network = PSIN.get_network_data(PSIN.get_transport_model(PSIN.get_template(m)))
    @test network.monitored == Set(["n1_n3", "n2_n3"])
    _solved_objective(m)

    container = PSIN.get_optimization_container(m)
    constraints = PSIN.get_constraint(
        container,
        CapacityReserveMarginConstraint(),
        PSIP.CapacityReserveMargin,
    )
    flow = PSIN.get_aux_variables(container)[PSIN.AuxVarKey(BranchFlow, PSIP.Portfolio)]
    capacity =
        JuMP.value.(
            PSIN.get_expression(
                container,
                PSIN.CumulativeCapacity(),
                thermal_type,
                "ContinuousInvestment",
            ),
        )
    demand2 = PSIP.get_technology(demand_type, p, "demand2")
    demand =
        TimeSeries.values(
            IS.get_time_series(
                IS.SingleTimeSeries,
                demand2,
                "ops_demand";
                year="2030",
                rep_day=1,
            ).data,
        ) .* PSIP.get_peak_demand_mw(demand2)
    for t in 1:24
        constraint = JuMP.constraint_object(constraints["reserve_margin", t])
        surplus = JuMP.value(constraint.func) - MOI.constant(constraint.set)
        @test surplus ≈
              capacity["cheap_thermal", 1] + flow["n1_n3", t] + flow["n2_n3", t] -
              1.3 * demand[t] atol = 1e-4
    end
end
