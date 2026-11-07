# Garver 6-bus system with every candidate line built (Mehrtash et al. 2020, Table 2)
const GARVER_LINES = [
    ("1-2", "1", "2", 0.4),
    ("1-4", "1", "4", 0.6),
    ("1-5", "1", "5", 0.2),
    ("2-3", "2", "3", 0.2),
    ("2-4", "2", "4", 0.4),
    ("3-5a", "3", "5", 0.2),
    ("3-5b", "3", "5", 0.2),
    ("3-6a", "3", "6", 0.48),
    ("3-6b", "3", "6", 0.48),
    ("4-6a", "4", "6", 0.3),
    ("4-6b", "4", "6", 0.3),
    ("4-6c", "4", "6", 0.3),
]

function _ptdf_from_lines(nodes, lines; reference_nodes=Set{String}(), tol=0.0)
    return PSIN.PTDF(
        nodes,
        [l[1] for l in lines],
        [(l[2], l[3]) for l in lines],
        [1.0 / l[4] for l in lines];
        reference_nodes=reference_nodes,
        tol=tol,
    )
end

_flows(ptdf, injections) = transpose(ptdf.data) * injections

@testset "PTDF of the Garver system" begin
    nodes = string.(1:6)
    ptdf = _ptdf_from_lines(nodes, GARVER_LINES; reference_nodes=Set(["1"]))
    # Mehrtash et al. (2020), Table 14: shift factors of one line in each corridor
    expected = Dict(
        "1-2" => [0.0, -0.4545, -0.2727, -0.2727, -0.1818, -0.2727],
        "1-4" => [0.0, -0.1818, -0.1777, -0.3719, -0.1184, -0.3148],
        "1-5" => [0.0, -0.3636, -0.5496, -0.3553, -0.6997, -0.4125],
        "2-3" => [0.0, 0.3636, -0.2790, 0.0125, -0.1860, -0.0732],
        "2-4" => [0.0, 0.1818, 0.0062, -0.2852, 0.0042, -0.1995],
        "3-5a" => [0.0, 0.1818, 0.2748, 0.1777, -0.1501, 0.2062],
        "3-6a" => [0.0, 0.0, 0.0857, -0.1714, 0.0571, -0.2429],
        "4-6a" => [0.0, 0.0, -0.0571, 0.1143, -0.0381, -0.1714],
    )
    for (branch, row) in expected, (node, value) in zip(nodes, row)
        @test isapprox(ptdf[branch, node], value; atol=1e-4)
    end
    # Parallel lines split the corridor flow by susceptance
    for node in nodes
        @test ptdf["3-5a", node] ≈ ptdf["3-5b", node]
        @test ptdf["4-6a", node] ≈ ptdf["4-6c", node]
    end
    @test ptdf.subnetworks == Dict("1" => nodes)

    cut = _ptdf_from_lines(nodes, GARVER_LINES; reference_nodes=Set(["1"]), tol=0.1)
    @test cut["2-4", "3"] == 0.0
    @test cut["2-3", "4"] == 0.0
    @test cut["1-2", "2"] == ptdf["1-2", "2"]
end

@testset "PTDF flows balance at every node but the reference" begin
    nodes = string.(1:6)
    ptdf = _ptdf_from_lines(nodes, GARVER_LINES; reference_nodes=Set(["1"]))
    injections = [-80.0, -240.0, 120.0, -160.0, -240.0, 600.0]
    flows = _flows(ptdf, injections)
    net_outflow = zeros(length(nodes))
    for ((_, from, to, _), flow) in zip(GARVER_LINES, flows)
        net_outflow[parse(Int, from)] += flow
        net_outflow[parse(Int, to)] -= flow
    end
    @test net_outflow[2:end] ≈ injections[2:end]
end

@testset "LODF matches recomputing the PTDF without the outaged line" begin
    nodes = string.(1:6)
    ptdf = _ptdf_from_lines(nodes, GARVER_LINES; reference_nodes=Set(["1"]))
    lodf = PSIN.LODF(ptdf)
    injections = [-80.0, -240.0, 120.0, -160.0, -240.0, 600.0]
    flows = Dict(zip(ptdf.axes[2], _flows(ptdf, injections)))
    for outaged in ("1-5", "2-3", "3-6a", "4-6b")
        @test lodf[outaged, outaged] == -1.0
        remaining = filter(l -> l[1] != outaged, GARVER_LINES)
        post = _ptdf_from_lines(nodes, remaining; reference_nodes=Set(["1"]))
        post_flows = Dict(zip(post.axes[2], _flows(post, injections)))
        for (monitored, _, _, _) in remaining
            @test isapprox(
                flows[monitored] + lodf[monitored, outaged] * flows[outaged],
                post_flows[monitored];
                atol=1e-9,
            )
        end
    end
end

@testset "PTDF of a network with islands" begin
    nodes = ["a1", "a2", "a3", "b1", "b2", "c1"]
    lines = [
        ("a12", "a1", "a2", 0.1),
        ("a23", "a2", "a3", 0.1),
        ("a31", "a3", "a1", 0.1),
        ("b12", "b1", "b2", 0.2),
    ]
    ptdf = @test_logs (:warn, r"No reference node") _ptdf_from_lines(
        nodes,
        lines;
        reference_nodes=Set(["a2"]),
    )
    @test ptdf.subnetworks ==
          Dict("a2" => ["a1", "a2", "a3"], "b1" => ["b1", "b2"], "c1" => ["c1"])
    @test ptdf["a12", "a1"] ≈ 2 / 3
    @test ptdf["a23", "a1"] ≈ -1 / 3
    @test ptdf["b12", "b2"] ≈ -1.0
    for branch in ("a12", "a23", "a31")
        @test ptdf[branch, "a2"] == 0.0
        @test ptdf[branch, "b2"] == 0.0
    end
    @test ptdf["b12", "a1"] == 0.0

    two_references =
        @test_logs (:warn, r"reference nodes") match_mode = :any _ptdf_from_lines(
            nodes,
            lines;
            reference_nodes=Set(["a1", "a2"]),
        )
    @test haskey(two_references.subnetworks, "a1")
    @test_throws ErrorException _ptdf_from_lines(
        nodes,
        [("bad", "a1", "a1", 0.1)];
        reference_nodes=Set(["a1"]),
    )
end

@testset "PTDF of the AC lines in a portfolio" begin
    portfolio, _ = test_2_zone_portfolio()
    nodes = [
        PSIP.Node(; name="n1", id=101, bus_type=PSY.ACBusTypes.REF),
        PSIP.Node(; name="n2", id=102),
        PSIP.Node(; name="n3", id=103),
    ]
    for node in nodes
        PSIP.add_region!(portfolio, node)
    end
    # The same per-unit reactance at two voltages: 0.1 * 230^2 ohms and 0.1 * 115^2 ohms
    for (id, (from, to, x, kv)) in
        enumerate(((1, 2, 5290.0, 230.0), (2, 3, 5290.0, 230.0), (3, 1, 1322.5, 115.0)))
        line = PSIP.NodalACTransportTechnology{PSY.ACBranch}(;
            name="line_$(from)$(to)",
            start_node=nodes[from],
            end_node=nodes[to],
            reactance=x,
            voltage=kv,
            capital_costs=PSIP.CapitalCost(LinearCurve(5000.0), 0.0),
            available=true,
            power_systems_type="ACBranch",
            id=id,
            financial_data=PSIP.TechnologyFinancialData(;
                capital_recovery_period=30,
                technology_base_year=2025,
                debt_fraction=0.6,
                debt_rate=0.04,
                return_on_equity=0.10,
                tax_rate=0.21,
            ),
        )
        PSIP.add_technology!(portfolio, line)
    end
    ptdf = PSIN.PTDF(portfolio)
    @test ptdf.axes == (["n1", "n2", "n3"], ["line_12", "line_23", "line_31"])
    @test collect(keys(ptdf.subnetworks)) == ["n1"]
    @test ptdf["line_12", "n2"] ≈ -2 / 3
    @test ptdf["line_23", "n2"] ≈ 1 / 3
    @test ptdf["line_31", "n2"] ≈ 1 / 3
end
