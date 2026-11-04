function amortize_overnight_term_to_base_year_dollars(
    container::SingleOptimizationContainer,
    technology::PSIP.Technology,
    proportional_term::Float64,
)
    financials = PSIP.get_financial_data(technology)
    base_year = get_base_year(container)
    discount_rate = get_discount_rate(container)
    inflation_rate = get_inflation_rate(container)
    wacc = PSIP.get_wacc(financials)
    tech_base_year = PSIP.get_technology_base_year(financials)
    capital_recovery_period = PSIP.get_capital_recovery_period(financials)
    capital_recovery_factor = wacc / (1 - (1 + wacc)^(-(capital_recovery_period)))
    lump_amortized_payments =
        (1 - (1 + discount_rate)^(-(capital_recovery_period))) / discount_rate
    discount_factor = 1 / (1 + discount_rate)
    dollars_to_base_year = (1.0 + inflation_rate)^(-(tech_base_year - base_year))
    amortized_proportional_term =
        proportional_term *
        capital_recovery_factor *
        lump_amortized_payments *
        dollars_to_base_year
    return amortized_proportional_term, discount_factor, base_year
end

"""
Present value, at the start of an investment period, of one unit paid at the start of each
year of the period.
"""
function investment_period_annuity_factor(discount_rate::Float64, inv_tuple)
    num_years =
        Dates.value(Dates.Year(inv_tuple[2])) - Dates.value(Dates.Year(inv_tuple[1])) + 1
    discount_factor = 1.0 / (1.0 + discount_rate)
    return sum(discount_factor^k for k in 0:(num_years - 1))
end
