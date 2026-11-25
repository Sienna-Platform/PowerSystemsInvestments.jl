@testset "Printing" begin
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
    set_requirement_model!(
        template,
        ["share_a", "share_b"],
        PSIP.EnergyShareRequirements,
        RequirementEnergyShare,
    )
    @test collect(values(PSIN.get_branch_models(template))) == [["test_branch"]]
    @test all(
        !in("test_branch", names) for names in values(PSIN.get_technology_models(template))
    )

    @testset "text/plain InvestmentModelTemplate" begin
        buf = IOBuffer()
        show(buf, MIME("text/plain"), template)
        out = String(take!(buf))

        @test occursin("ThermalStandard", out)
        @test occursin("ContinuousInvestment", out)
        @test occursin("BasicDispatch", out)
        @test occursin("Requirement Models", out)
        @test occursin("EnergyShareRequirements", out)
        @test occursin("share_a, share_b", out)

        @test occursin("Template Model", out)
        @test occursin("Technology Models", out)
        @test occursin("Branch Models", out)
        @test occursin("AggregateTransportTechnology", out)
        @test occursin("MultiRegionBalanceModel", out)
        @test occursin("DiscountedCashFlow", out)
    end

    @testset "text/html InvestmentModelTemplate" begin
        buf = IOBuffer()
        show(buf, MIME("text/html"), template)
        out = String(take!(buf))

        @test occursin("ThermalStandard", out)
        @test occursin("ContinuousInvestment", out)
        @test occursin("BasicDispatch", out)
        @test occursin("Requirement Models", out)
        @test occursin("EnergyShareRequirements", out)
        @test occursin("share_a, share_b", out)

        @test occursin("Template Model", out)
        @test occursin("Technology Models", out)
        @test occursin("Branch Models", out)
        @test occursin("AggregateTransportTechnology", out)
        @test occursin("<table", out)
    end
end
