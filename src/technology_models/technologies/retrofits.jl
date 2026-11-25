_check_retrofit_source(::PSIP.SupplyTechnology) = nothing
function _check_retrofit_source(source::PSIP.Technology)
    throw(
        IS.DataFormatError(
            "Only supply technologies can be retrofitted, but $(PSIP.get_name(source)) " *
            "is a $(nameof(typeof(source)))",
        ),
    )
end

function _retrofit_source(
    portfolio::PSIP.Portfolio,
    names_to_model_map::Dict{String, TechnologyModel},
    name::String,
    option::PSIP.Technology,
)
    attributes = PSIP.get_supplemental_attributes(PSIP.RetrofitPotential, option)
    if length(attributes) != 1
        throw(
            IS.DataFormatError(
                "Retrofit option $name needs one RetrofitPotential, shared with the " *
                "technologies it retrofits, but it has $(length(attributes))",
            ),
        )
    end
    retrofit = only(attributes)
    others = [
        t for t in PSIP.get_attached_components(portfolio, retrofit) if
        PSIP.get_name(t) != name
    ]
    if length(others) != 1
        throw(
            IS.DataFormatError(
                "The RetrofitPotential of retrofit option $name must be attached to it and " *
                "to one source technology, but it is attached to $(length(others)) others",
            ),
        )
    end
    source = only(others)
    source_name = PSIP.get_name(source)
    _check_retrofit_source(source)
    PSIP.get_available(source) || throw(
        IS.DataFormatError("Source $source_name of retrofit option $name is unavailable"),
    )
    if !haskey(names_to_model_map, source_name)
        throw(
            IS.ConflictingInputsError(
                "Source $source_name of retrofit option $name has no technology model",
            ),
        )
    end
    if get_investment_formulation(names_to_model_map[source_name]) == RetrofitInvestment
        throw(
            IS.ConflictingInputsError(
                "Retrofit option $name retrofits $source_name, which is a retrofit option",
            ),
        )
    end
    # A supply technology in several regions has a build variable per region
    length(PSIP.get_region(option)) == 1 ||
        throw(IS.DataFormatError("Retrofit option $name must be in one region"))
    if PSIP.get_capacity_limits(source).min > 0.0
        throw(
            IS.DataFormatError(
                "Source $source_name of retrofit option $name has a minimum capacity, " *
                "which retrofits don't support",
            ),
        )
    end
    efficiency = PSIP.get_retrofit_efficiency(retrofit)
    if !isfinite(efficiency) || efficiency <= 0.0
        throw(
            IS.DataFormatError(
                "retrofit_efficiency of retrofit option $name must be positive and finite",
            ),
        )
    end
    eligible = PSIP.get_eligible_generators(retrofit)
    existing = [
        unit for
        attribute in PSIP.get_supplemental_attributes(PSIP.ExistingDevices, source) for
        unit in PSIP.get_existing_devices(attribute)
    ]
    not_existing = setdiff(eligible, existing)
    if !isempty(not_existing)
        throw(
            IS.DataFormatError(
                "Retrofit units $(join(not_existing, ", ")) of $source_name are not among " *
                "its ExistingDevices",
            ),
        )
    end
    allunique(eligible) || throw(
        IS.DataFormatError("RetrofitPotential of retrofit option $name repeats a unit"),
    )
    return source, retrofit
end

# Runs after the capital model's argument stage, before anything copies the sources'
# CumulativeCapacity, which it reduces in place.
function link_retrofits!(
    container::SingleOptimizationContainer,
    portfolio::PSIP.Portfolio,
    names_to_model_map::Dict{String, TechnologyModel},
)
    options = sort!(
        [
            (name, PSIP.get_technology(get_technology_type(model), portfolio, name)) for
            (name, model) in names_to_model_map if
            get_investment_formulation(model) == RetrofitInvestment
        ];
        by=first,
    )
    filter!(x -> PSIP.get_available(last(x)), options)
    isempty(options) && return
    time_steps = get_investment_time_steps(get_time_mapping(container))
    jump_model = get_jump_model(container)
    store_names = get_store_variable_names(get_settings(container))

    links = Tuple{String, PSIP.Technology, PSIP.Technology, PSIP.RetrofitPotential}[]
    unit_capacity = Dict{String, Float64}()
    for (name, option) in options
        source, retrofit = _retrofit_source(portfolio, names_to_model_map, name, option)
        push!(links, (name, option, source, retrofit))
        for unit in PSIP.get_eligible_generators(retrofit)
            get!(unit_capacity, "$(PSIP.get_name(source))__$unit") do
                PSIP.get_retrofit_capacity_mw(
                    portfolio,
                    source,
                    PSIP.RetrofitPotential(; id=0, eligible_generators=[unit]),
                )
            end
        end
    end

    retrofit_capacity = add_expression_container!(
        container,
        RetrofitCapacity(),
        PSIP.Portfolio,
        sort(unique(PSIP.get_name(source) for (_, _, source, _) in links)),
        time_steps,
    )
    # Source capacity (MW) each option converts from each eligible unit
    allocation = add_variable_container!(
        container,
        RetrofitAllocationVariable(),
        PSIP.Portfolio,
        [
            "$(name)__$unit" for (name, _, _, retrofit) in links for
            unit in PSIP.get_eligible_generators(retrofit)
        ],
    )
    con_option = add_constraints_container!(
        container,
        RetrofitPotentialConstraint(),
        PSIP.Portfolio,
        first.(links);
        meta="option",
    )
    unit_names = sort(collect(keys(unit_capacity)))
    unit_allocations = Dict(unit => JuMP.AffExpr(0.0) for unit in unit_names)
    for (name, option, source, retrofit) in links
        source_name = PSIP.get_name(source)
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
            string(get_investment_formulation(names_to_model_map[source_name])),
        )
        efficiency = PSIP.get_retrofit_efficiency(retrofit)
        for p in time_steps, q in first(time_steps):p
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
        allocated = JuMP.AffExpr(0.0)
        for unit in PSIP.get_eligible_generators(retrofit)
            base_name = store_names ? "RetrofitAllocationVariable_{$(name)__$unit}" : ""
            x =
                allocation["$(name)__$unit"] =
                    JuMP.@variable(jump_model, base_name = base_name, lower_bound = 0.0)
            JuMP.add_to_expression!(allocated, x)
            JuMP.add_to_expression!(unit_allocations["$(source_name)__$unit"], x)
        end
        con_option[name] = JuMP.@constraint(
            jump_model,
            sum(build[name, q] for q in time_steps) / efficiency == allocated
        )
    end

    con_unit = add_constraints_container!(
        container,
        RetrofitPotentialConstraint(),
        PSIP.Portfolio,
        unit_names;
        meta="unit",
    )
    for unit in unit_names
        con_unit[unit] =
            JuMP.@constraint(jump_model, unit_allocations[unit] <= unit_capacity[unit])
    end
    return
end
