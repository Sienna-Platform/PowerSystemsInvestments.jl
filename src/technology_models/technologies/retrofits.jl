# Retrofits (design in .claude/plans/retrofit_design.md). A technology with RetrofitInvestment
# (the option) is built only by converting existing capacity of the technology it shares a
# RetrofitPotential with (the source): each MW of option built takes 1 / retrofit_efficiency MW
# of the source, from the period it is built.

_check_retrofit_source(::PSIP.SupplyTechnology) = nothing
function _check_retrofit_source(source::PSIP.Technology)
    error(
        "Only supply technologies can be retrofitted; $(PSIP.get_name(source)) is a " *
        "$(nameof(typeof(source))).",
    )
end

# Links every retrofit option to its source: the source's cumulative capacity loses what is
# retrofitted, which is at most the capacity of the eligible units. Runs after the argument
# stage of all technologies, before anything reads the sources' capacity.
function link_retrofits!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    names_to_model_map::Dict{String, TechnologyModel},
)
    options = [
        (name, model) for (name, model) in names_to_model_map if
        get_investment_formulation(model) == RetrofitInvestment
    ]
    isempty(options) && return
    time_steps = get_investment_time_steps(get_time_mapping(container))
    jump_model = get_jump_model(container)

    # Source capacity retrofitted over the horizon (MW of source) and its limit, per option
    # and per source
    option_retrofits = Dict{String, Tuple{JuMP.AffExpr, Float64}}()
    source_retrofits =
        Dict{String, Tuple{JuMP.AffExpr, PSIP.SupplyTechnology, Set{String}}}()
    options_per_source = Dict{String, Int}()
    links = []
    for (name, model) in sort(options; by=first)
        option = PSIP.get_technology(get_technology_type(model), portfolio, name)
        attributes = PSIP.get_supplemental_attributes(PSIP.RetrofitPotential, option)
        if length(attributes) != 1
            error(
                "Retrofit option $name needs one RetrofitPotential, shared with the " *
                "technology it retrofits; it has $(length(attributes)).",
            )
        end
        retrofit = only(attributes)
        others = [
            t for t in PSIP.get_associated_technologies(portfolio, retrofit) if
            PSIP.get_name(t) != name
        ]
        if length(others) != 1
            error(
                "The RetrofitPotential of retrofit option $name must be attached to it and " *
                "to one source technology; it is attached to $(length(others)) others.",
            )
        end
        source = only(others)
        source_name = PSIP.get_name(source)
        _check_retrofit_source(source)
        if !haskey(names_to_model_map, source_name)
            error("Source $source_name of retrofit option $name has no technology model.")
        end
        source_model = names_to_model_map[source_name]
        if get_investment_formulation(source_model) == RetrofitInvestment
            error(
                "Retrofit option $name retrofits $source_name, which is a retrofit option.",
            )
        end
        # A supply technology in several regions has a build variable per region
        if length(PSIP.get_region(option)) != 1
            error("Retrofit option $name must be in one region.")
        end
        if PSIP.get_capacity_limits(source).min > 0.0
            error(
                "Source $source_name of retrofit option $name has a minimum capacity, which " *
                "is not supported with retrofits.",
            )
        end
        efficiency = PSIP.get_retrofit_efficiency(retrofit)
        if efficiency <= 0.0
            error("retrofit_efficiency of retrofit option $name must be positive.")
        end
        existing = [
            unit for
            attribute in PSIP.get_supplemental_attributes(PSIP.ExistingDevices, source)
            for unit in PSIP.get_existing_devices(attribute)
        ]
        eligible = PSIP.get_eligible_generators(retrofit)
        not_existing = setdiff(eligible, existing)
        if !isempty(not_existing)
            error(
                "Retrofit units $(join(not_existing, ", ")) of $source_name are not among " *
                "its ExistingDevices.",
            )
        end

        build = get_variable(
            container,
            BuildCapacity(),
            typeof(option),
            string(RetrofitInvestment),
        )
        capacity = get_expression(
            container,
            CumulativeCapacity(),
            typeof(source),
            string(get_investment_formulation(source_model)),
        )
        push!(links, (source_name, capacity, name, build, efficiency))
        retrofitted = JuMP.AffExpr(0.0)
        for q in time_steps
            JuMP.add_to_expression!(retrofitted, 1.0 / efficiency, build[name, q])
        end
        option_retrofits[name] =
            (retrofitted, PSIP.get_retrofit_capacity_mw(portfolio, source, retrofit))
        total, _, units =
            get!(source_retrofits, source_name, (JuMP.AffExpr(0.0), source, Set{String}()))
        JuMP.add_to_expression!(total, retrofitted)
        union!(units, eligible)
        options_per_source[source_name] = get(options_per_source, source_name, 0) + 1
    end

    # The source loses 1 / efficiency MW for every MW of option built up to each period. The
    # converted capacity (RetrofitCapacity) still counts toward the source's maximum
    retrofit_capacity = add_expression_container!(
        container,
        RetrofitCapacity(),
        PSIP.Portfolio,
        sort(collect(keys(source_retrofits))),
        time_steps,
    )
    for (source_name, capacity, name, build, efficiency) in links, p in time_steps
        for q in time_steps
            q <= p || continue
            JuMP.add_to_expression!(
                retrofit_capacity[source_name, p],
                1.0 / efficiency,
                build[name, q],
            )
            JuMP.add_to_expression!(
                capacity[source_name, p],
                -1.0 / efficiency,
                build[name, q],
            )
        end
    end

    # Each option converts at most its eligible units; a source with several options converts
    # at most the units any of them lists
    option_names = sort(collect(keys(option_retrofits)))
    con = add_constraints_container!(
        container,
        RetrofitPotentialConstraint(),
        PSIP.Portfolio,
        option_names;
        meta="option",
    )
    for name in option_names
        retrofitted, limit = option_retrofits[name]
        con[name] = JuMP.@constraint(jump_model, retrofitted <= limit)
    end
    multiple = sort([name for (name, n) in options_per_source if n > 1])
    isempty(multiple) && return
    con_source = add_constraints_container!(
        container,
        RetrofitPotentialConstraint(),
        PSIP.Portfolio,
        multiple;
        meta="source",
    )
    for source_name in multiple
        total, source, units = source_retrofits[source_name]
        limit = PSIP.get_retrofit_capacity_mw(
            portfolio,
            source,
            PSIP.RetrofitPotential(; id=0, eligible_generators=collect(units)),
        )
        con_source[source_name] = JuMP.@constraint(jump_model, total <= limit)
    end
    return
end
