function amortize_overnight_term_to_base_year_dollars(
    container::SingleOptimizationContainer,
    technology::PSIP.Technology,
    proportional_term::Float64,
)
    financials = PSIP.get_financial_data(technology)
    base_year = get_base_year(container)
    discount_rate = PSIP.get_discount_rate(financials)
    inflation_rate = PSIP.get_inflation_rate(financials)
    wacc = PSIP.get_wacc(financials)
    tech_base_year = PSIP.get_technology_base_year(financials)
    capital_recovery_period = PSIP.get_capital_recovery_period(financials)
    capital_recovery_factor = wacc / (1 - (1 + wacc)^(-(capital_recovery_period)))
    # Present value of an annuity; its limit is the period itself at a zero discount rate.
    lump_amortized_payments = if iszero(discount_rate)
        Float64(capital_recovery_period)
    else
        (1 - (1 + discount_rate)^(-(capital_recovery_period))) / discount_rate
    end
    discount_factor = 1 / (1 + discount_rate)
    dollars_to_base_year = (1.0 + inflation_rate)^(-(tech_base_year - base_year))
    amortized_proportional_term =
        proportional_term *
        capital_recovery_factor *
        lump_amortized_payments *
        dollars_to_base_year
    return amortized_proportional_term, discount_factor, base_year
end
