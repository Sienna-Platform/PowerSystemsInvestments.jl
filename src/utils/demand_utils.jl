# Demand of each DemandRequirement in MW (DemandExpression): its normalized "ops_demand" shape
# times its peak in the year of each representative period
function initialize_demands!(container::SingleOptimizationContainer, p::PSIP.Portfolio)
    demands = collect(PSIP.get_technologies(PSIP.DemandRequirement, p))
    isempty(demands) && return
    time_mapping = get_time_mapping(container)
    consecutive_slices = get_consecutive_slices(time_mapping)
    time_stamps = get_time_stamps(time_mapping)
    # Year of the first time stamp of each representative period
    years = Dict(
        op_ix => Dates.year(time_stamps[first(consecutive_slices[op_ix])]) for
        op_ix in get_all_indexes(time_mapping)
    )
    last_year = maximum(values(years))
    series_name = get_default_time_series_names(PSIP.DemandRequirement)
    expression = add_expression_container!(
        container,
        DemandExpression(),
        PSIP.Portfolio,
        PSIP.get_name.(demands),
        1:get_total_period_count(time_mapping),
    )

    for d in demands
        name = PSIP.get_name(d)
        conformity = PSIP.get_conformity(d)
        if PSIP.is_new(d)
            if conformity == PSY.LoadConformity.UNDEFINED
                error(
                    "New demand $name has an undefined conformity. Set it to CONFORMING " *
                    "or NON_CONFORMING.",
                )
            end
            if PSIP.get_peak_demand_mw(d) <= 0.0
                error("New demand $name needs a positive peak_demand_mw.")
            end
            if PSIP.get_construction_year(d) > last_year
                @warn "Demand $name is built in $(PSIP.get_construction_year(d)), after " *
                      "the last modeled year ($last_year), so it is never active."
            end
        elseif PSIP.get_peak_demand_mw(d) != 0.0
            @warn "Demand $name has existing loads, so its peak_demand_mw is ignored and " *
                  "its peak comes from the base system."
        end
        if !IS.has_time_series(d, IS.SingleTimeSeries, series_name)
            error("Demand $name needs a \"$series_name\" time series.")
        end
        # Only conforming demands grow (an undefined conformity is conforming)
        growth = PSIP.get_growth_rate(d)
        if conformity == PSY.LoadConformity.NON_CONFORMING && growth != 0.0
            @warn "Demand $name is non-conforming, so its growth_rate is ignored."
            growth = 0.0
        end

        # Growth is from the base year, or for new demands from their construction year;
        # new demands are zero before it
        base_peak = PSIP.get_peak_demand_mw(p, d)
        reference_year =
            PSIP.is_new(d) ? PSIP.get_construction_year(d) : get_base_year(container)
        exceeds_peak = false
        for (op_ix, year) in years
            time_slices = consecutive_slices[op_ix]
            time_series = retrieve_ops_time_series(d, op_ix, time_mapping)
            check_initial_timestamp(time_series, d, time_stamps[first(time_slices)], op_ix)
            shape = TimeSeries.values(time_series.data)
            exceeds_peak |= maximum(shape) > 1.0
            year < reference_year && PSIP.is_new(d) && continue
            peak = base_peak * (1.0 + growth)^(year - reference_year)
            for (t, value) in zip(time_slices, shape)
                JuMP.add_to_expression!(expression[name, t], value * peak)
            end
        end
        if exceeds_peak
            @warn "The \"$series_name\" time series of demand $name exceeds 1, but it " *
                  "should be normalized to its peak."
        end
    end
    return
end
