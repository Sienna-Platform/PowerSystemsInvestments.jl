function _financials(; discount_rate, inflation_rate=0.02, technology_base_year=2025)
    return TechnologyFinancialData(;
        capital_recovery_period=20,
        technology_base_year=technology_base_year,
        debt_fraction=0.5,
        debt_rate=0.05,
        return_on_equity=0.1,
        tax_rate=0.2,
        discount_rate=discount_rate,
        inflation_rate=inflation_rate,
        interest_rate=0.04,
    )
end

function _thermal(name, financials)
    return SupplyTechnology{ThermalStandard}(;
        name=name,
        available=true,
        power_systems_type="ThermalStandard",
        financial_data=financials,
    )
end

@testset "Financial rates come from each technology" begin
    container = PSIN.SingleOptimizationContainer(PSIN.Settings(Portfolio()), nothing)
    PSIN.set_base_year!(container, 2025)

    low = _thermal("low", _financials(; discount_rate=0.03))
    high = _thermal("high", _financials(; discount_rate=0.10))
    term_low, factor_low, base_low =
        PSIN.amortize_overnight_term_to_base_year_dollars(container, low, 1000.0)
    term_high, factor_high, base_high =
        PSIN.amortize_overnight_term_to_base_year_dollars(container, high, 1000.0)
    @test base_low == base_high == 2025
    @test factor_low ≈ 1 / 1.03
    @test factor_high ≈ 1 / 1.10
    # A higher discount rate weighs the recovery payments less.
    @test term_low > term_high

    # Inflation converts from the technology's base year to the model base year.
    vintage = _thermal(
        "vintage",
        _financials(; discount_rate=0.03, inflation_rate=0.02, technology_base_year=2020),
    )
    term_vintage, _, _ =
        PSIN.amortize_overnight_term_to_base_year_dollars(container, vintage, 1000.0)
    @test term_vintage ≈ term_low * 1.02^5

    # A zero discount rate takes the annuity's limit instead of dividing by zero.
    zero_rate = _thermal("zero", _financials(; discount_rate=0.0))
    term_zero, factor_zero, _ =
        PSIN.amortize_overnight_term_to_base_year_dollars(container, zero_rate, 1000.0)
    @test isfinite(term_zero)
    @test factor_zero == 1.0
    wacc = PSIP.get_wacc(PSIP.get_financial_data(zero_rate))
    crf = wacc / (1 - (1 + wacc)^-20)
    @test term_zero ≈ 1000.0 * crf * 20
end

@testset "DiscountedCashFlow carries the model base year" begin
    periods = [(Date(Month(1), Year(2030)), Date(Month(12), Year(2034)))]
    capital = DiscountedCashFlow(Year(2030), periods)
    @test capital.base_year == Year(2030)
    @test !hasfield(DiscountedCashFlow, :discount_rate)
end
