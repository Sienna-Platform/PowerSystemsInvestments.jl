@testset "Printing" begin
    p_5bus, op_days = test_2_zone_portfolio()
    # 2 representative days (24-hours for 5 years each)
    weights = [365 * 5, 365 * 5]
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
        TransportModel(MultiRegionBalanceModel, use_slacks=false),
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

    @testset "text/plain InvestmentModelTemplate" begin
        buf = IOBuffer()
        show(buf, MIME("text/plain"), template)
        out = String(take!(buf))

        @test occursin("Template Model", out)
        @test occursin("Technology Models", out)
        @test occursin("MultiRegionBalanceModel", out)
        @test occursin("DiscountedCashFlow", out)
    end

    @testset "text/html InvestmentModelTemplate" begin
        buf = IOBuffer()
        show(buf, MIME("text/html"), template)
        out = String(take!(buf))

        @test occursin("Template Model", out)
        @test occursin("Technology Models", out)
        @test occursin("<table", out)
    end
end
