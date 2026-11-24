const FEASIBILITY_DAY = collect(DateTime(2030, 7, 15, 0):Hour(1):DateTime(2030, 7, 15, 23))
const FEASIBILITY_DEMAND = 100.0

# 2-zone portfolio with one feasibility day after the two operational days. The feasibility
# day needs the demand and wind time series of every representative period.
function _feasibility_portfolio()
    p, op_days = test_2_zone_portfolio()
    feasibility_rep_day = length(op_days) + 1
    for name in ["demand1", "demand2"]
        demand = PSIP.get_technology(PSIP.DemandRequirement{PSY.PowerLoad}, p, name)
        PSIP.add_time_series!(
            p,
            demand,
            SingleTimeSeries(;
                name="ops_demand",
                data=TimeArray(FEASIBILITY_DAY, fill(FEASIBILITY_DEMAND, 24)),
            );
            year="2030",
            rep_day=feasibility_rep_day,
        )
    end
    wind = PSIP.get_technology(PSIP.SupplyTechnology{PSY.RenewableDispatch}, p, "wind")
    PSIP.add_time_series!(
        p,
        wind,
        SingleTimeSeries(;
            name="ops_variable_cap_factor",
            data=TimeArray(FEASIBILITY_DAY, fill(0.3, 24)),
        );
        year="2030",
        rep_day=feasibility_rep_day,
    )
    return p, op_days
end

function _feasibility_model(
    p,
    op_days,
    transport_model,
    demand_names,
    branches;
    storage=false,
)
    periods = [
        (Date(Month(1), Year(2030)), Date(Month(12), Year(2034))),
        (Date(Month(1), Year(2035)), Date(Month(12), Year(2039))),
    ]
    template = InvestmentModelTemplate(
        DiscountedCashFlow(0.07, Year(2025), periods),
        OperationalRepresentativeDays(op_days, [365, 365]),
        RepresentativePeriods([FEASIBILITY_DAY]),
        transport_model,
    )
    set_technology_model!(
        template,
        demand_names,
        PSIP.DemandRequirement{PSY.PowerLoad},
        StaticLoadInvestment,
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
        ["wind"],
        PSIP.SupplyTechnology{PSY.RenewableDispatch},
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility,
    )
    if storage
        set_technology_model!(
            template,
            ["test_storage"],
            PSIP.StorageTechnology{PSY.EnergyReservoirStorage},
            ContinuousInvestment,
            CyclicalStorageDispatch,
            BasicDispatchFeasibility,
        )
    end
    for (names, branch_type) in branches
        set_technology_model!(
            template,
            names,
            branch_type,
            ContinuousInvestment,
            BasicDispatch,
            BasicDispatchFeasibility,
        )
    end
    m = InvestmentModel(
        template,
        SingleInstanceSolve,
        p;
        optimizer=HiGHS.Optimizer,
        portfolio_to_file=false,
        store_variable_names=true,
    )
    @test build!(m; output_dir=mktempdir(; cleanup=true)) ==
          IS.Optimization.ModelBuildStatusModule.ModelBuildStatus.BUILT
    return m
end

_first_feasibility_step(container) =
    first(PSIN.get_feasibility_time_steps(PSIN.get_time_mapping(container)))

@testset "Feasibility periods in a single region" begin
    p, op_days = _feasibility_portfolio()
    m = _feasibility_model(
        p,
        op_days,
        TransportModel(SingleRegionBalanceModel, use_slacks=false),
        ["demand1"],
        # The branch is internal to the region and adds no import capacity.
        [(["test_branch"], PSIP.AggregateTransportTechnology{PSY.ACBranch})],
    )
    container = PSIN.get_optimization_container(m)
    t = _first_feasibility_step(container)
    thermal_type = PSIP.SupplyTechnology{PSY.ThermalStandard}
    build = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        thermal_type,
        "ContinuousInvestment",
    )
    feasibility = PSIN.get_constraint(
        container,
        PSIN.SingleRegionBalanceFeasibilityConstraint(),
        PSIP.Portfolio,
    )
    # The installed capacity covers the demand of the feasibility day.
    @test JuMP.normalized_coefficient(feasibility[t], build["cheap_thermal", 1]) == 1.0
    @test JuMP.normalized_rhs(feasibility[t]) == FEASIBILITY_DEMAND
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
end

@testset "Feasibility periods in zones with transmission" begin
    p, op_days = _feasibility_portfolio()
    branch_type = PSIP.AggregateTransportTechnology{PSY.ACBranch}
    m = _feasibility_model(
        p,
        op_days,
        TransportModel(MultiRegionBalanceModel, use_slacks=false),
        ["demand1", "demand2"],
        [(["test_branch"], branch_type)],
    )
    container = PSIN.get_optimization_container(m)
    t = _first_feasibility_step(container)
    zones = PSIP.get_name.(PSIP.get_regions(PSIP.Zone, p))
    branch_build = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        branch_type,
        "ContinuousInvestment",
    )[
        "test_branch",
        1,
    ]
    imports =
        PSIN.get_expression(container, PSIN.FeasibilityImportCapacity(), PSIP.Portfolio)
    feasibility = PSIN.get_constraint(
        container,
        PSIN.MultiRegionBalanceFeasibilityConstraint(),
        PSIP.Portfolio,
    )
    system = PSIN.get_constraint(
        container,
        PSIN.MultiRegionBalanceFeasibilityConstraint(),
        PSIP.Portfolio,
        "system",
    )
    # Either zone can import over the branch, but the branch adds no capacity to the system.
    for zone in zones
        @test JuMP.coefficient(imports[zone, t], branch_build) == 1.0
        @test JuMP.normalized_coefficient(feasibility[zone, t], branch_build) == 1.0
    end
    @test JuMP.normalized_coefficient(system[t], branch_build) == 0.0
    @test JuMP.normalized_rhs(system[t]) == 2 * FEASIBILITY_DEMAND
    # Operational time steps have no import capacity.
    @test JuMP.coefficient(imports[first(zones), 1], branch_build) == 0.0
    # The flow over the branch is limited by its installed capacity in the feasibility periods.
    flow_limit = PSIN.get_constraint(
        container,
        PSIN.ActivePowerLimitsConstraint(),
        branch_type,
        "BasicDispatch",
    )
    @test JuMP.normalized_coefficient(flow_limit["test_branch", t], branch_build) == -1.0
    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
end

# All the supply is at Node_1, so Node_2 can only cover its demand by importing
function _test_nodal_feasibility(transport)
    p, op_days = _feasibility_portfolio()
    max_id = maximum(PSIP.get_id(r) for r in PSIP.get_regions(PSIP.RegionTopology, p))
    nodes = [
        PSIP.Node(;
            name="Node_$i",
            id=max_id + i,
            bus_type=i == 1 ? PSY.ACBusTypes.REF : PSY.ACBusTypes.PQ,
        ) for i in 1:2
    ]
    for node in nodes
        PSIP.add_region!(p, node)
    end
    supply = [
        (PSIP.SupplyTechnology{PSY.ThermalStandard}, "cheap_thermal"),
        (PSIP.SupplyTechnology{PSY.ThermalStandard}, "expensive_thermal"),
        (PSIP.SupplyTechnology{PSY.RenewableDispatch}, "wind"),
    ]
    for (technology_type, name) in supply
        PSIP.set_region!(PSIP.get_technology(technology_type, p, name), [nodes[1]])
    end
    storage_type = PSIP.StorageTechnology{PSY.EnergyReservoirStorage}
    PSIP.set_region!(PSIP.get_technology(storage_type, p, "test_storage"), [nodes[2]])
    for (name, node) in zip(["demand1", "demand2"], nodes)
        demand = PSIP.get_technology(PSIP.DemandRequirement{PSY.PowerLoad}, p, name)
        PSIP.set_region!(demand, [node])
    end
    branch_type = PSIP.NodalACTransportTechnology{PSY.ACBranch}
    line = branch_type(;
        name="line",
        start_node=nodes[1],
        end_node=nodes[2],
        reactance=0.1 * 230.0^2,
        voltage=230.0,
        # The demand of Node_2 reaches about 1300 MW in 2035.
        capacity_limits=(min=0, max=5000),
        capital_costs=PSIP.CapitalCost(LinearCurve(5000.0), 0.0),
        available=true,
        power_systems_type="ACBranch",
        id=100,
        financial_data=PSIP.TechnologyFinancialData(;
            capital_recovery_period=30,
            technology_base_year=2025,
            debt_fraction=0.6,
            debt_rate=0.04,
            return_on_equity=0.10,
            tax_rate=0.21,
        ),
    )
    PSIP.add_technology!(p, line)

    m = _feasibility_model(
        p,
        op_days,
        TransportModel(transport, use_slacks=false),
        ["demand1", "demand2"],
        [(["line"], branch_type)];
        storage=true,
    )
    container = PSIN.get_optimization_container(m)
    t = _first_feasibility_step(container)
    line_build = PSIN.get_variable(
        container,
        PSIN.BuildCapacity(),
        branch_type,
        "ContinuousInvestment",
    )[
        "line",
        1,
    ]
    feasibility = PSIN.get_constraint(
        container,
        PSIN.NodalBalanceFeasibilityConstraint(),
        PSIP.Portfolio,
    )
    @test JuMP.normalized_coefficient(feasibility["Node_2", t], line_build) == 1.0
    storage_build = PSIN.get_variable(
        container,
        PSIN.BuildPowerCapacity(),
        storage_type,
        "ContinuousInvestment",
    )[
        "test_storage",
        1,
    ]
    @test JuMP.normalized_coefficient(feasibility["Node_2", t], storage_build) == 1.0
    @test JuMP.normalized_rhs(feasibility["Node_2", t]) == FEASIBILITY_DEMAND
    if transport == NodalBalanceModel
        flow_limit = PSIN.get_constraint(
            container,
            PSIN.FlowActivePowerUpperBoundConstraint(),
            branch_type,
            "BasicDispatch",
        )
        @test JuMP.normalized_coefficient(flow_limit["line", t], line_build) == -1.0
    end

    @test solve!(m) == PSIN.RunStatus.SUCCESSFULLY_FINALIZED
    line_capacity = filter(
        r -> r.name == "line" && r.time_index == 1,
        read_expression(
            m,
            PSIN.ExpressionKey(CumulativeCapacity, branch_type, "ContinuousInvestment"),
        ),
    )
    @test only(line_capacity.value) >= FEASIBILITY_DEMAND - 1e-6
    return
end

@testset "Feasibility periods in nodes with transmission" begin
    for transport in (NodalBalanceModel, NodalPTDFModel)
        _test_nodal_feasibility(transport)
    end
end
