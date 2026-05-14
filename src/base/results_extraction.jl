# Results Extraction API for OptimizationProblemResults
# Provides methods to read decision variables, constraints, duals, and objective values
# from solved investment optimization models

"""
    get_objective_value(res::OptimizationProblemResults) -> Float64

Returns the optimal objective value (total annualized cost in dollars).
"""
function get_objective_value(res::ISOPT.OptimizationProblemResults)
    try
        # Access path: res.model.internal.container.JuMPmodel
        if hasfield(typeof(res), :model)
            model = res.model
            if hasfield(typeof(model), :internal)
                internal = model.internal
                if hasfield(typeof(internal), :container)
                    container = internal.container
                    if hasfield(typeof(container), :JuMPmodel)
                        jmodel = container.JuMPmodel
                        if !isnothing(jmodel)
                            return JuMP.objective_value(jmodel)
                        end
                    end
                end
            end
        end
    catch e
        @warn "Could not extract objective value: $e"
    end
    return NaN
end

"""
    read_variable(
        res::OptimizationProblemResults,
        variable_key::VariableKey,
        technology_type,
        investment_type::String
    ) -> DataFrame

Reads a decision variable from results and returns as DataFrame.
Supports: BuildCapacity, ActivePowerVariable, StorageEnergyVariable, etc.

Example:
```julia
cap_var = read_variable(res,
    VariableKey(BuildCapacity,
                SupplyTechnology{RenewableDispatch},
                "ContinuousInvestment"))
```

Returns DataFrame with columns: technology, value
"""
function read_variable(
    res::ISOPT.OptimizationProblemResults,
    variable_key::ISOPT.VariableKey,
    _technology_type=nothing,
    _investment_type::String=""
)
    results_df = DataFrame(
        technology = String[],
        time_period_idx = Union{Int, Missing}[],
        time_period = Union{String, Missing}[],
        value = Float64[],
    )

    try
        # Access path: res.model.internal.container.variables
        if hasfield(typeof(res), :model)
            model = res.model

            # Try to get TimeMapping for converting indices to date ranges
            time_mapping = nothing
            if hasfield(typeof(model), :internal) && hasfield(typeof(model.internal), :container)
                container = model.internal.container
                try
                    time_mapping = get_time_mapping(container)
                catch
                    # TimeMapping not available, continue without it
                end
            end

            if hasfield(typeof(model), :internal)
                internal = model.internal
                if hasfield(typeof(internal), :container)
                    container = internal.container
                    if hasfield(typeof(container), :variables)
                        vars = container.variables

                        # Filter variables matching the given variable_key
                        for (var_key, var_array) in vars
                            # Check if this variable key matches the requested variable type
                            if typeof(var_key) == typeof(variable_key)
                                # For investment variables (BuildCapacity, etc), axes are (technology_name, investment_period)
                                try
                                    if ndims(var_array) == 2
                                        # 2D array: (technology, time_period) indexing preserved
                                        tech_names, time_periods = axes(var_array)
                                        for tech_name in tech_names, time_period in time_periods
                                            val = JuMP.value(var_array[tech_name, time_period])

                                            # Map investment period index to date range if TimeMapping available
                                            time_period_label = missing
                                            if !isnothing(time_mapping) && isa(time_period, Int)
                                                try
                                                    inv_intervals = time_mapping.investment.time_stamps
                                                    if time_period <= length(inv_intervals)
                                                        date_range = inv_intervals[time_period]
                                                        start_date = Dates.format(date_range[1], "yyyy-mm-dd")
                                                        end_date = Dates.format(date_range[2], "yyyy-mm-dd")
                                                        time_period_label = "$start_date to $end_date"
                                                    end
                                                catch e
                                                    # If mapping fails, leave label as missing
                                                end
                                            end

                                            # Include all values, including zeros
                                            push!(results_df, (
                                                technology=string(tech_name),
                                                time_period_idx=time_period,
                                                time_period=time_period_label,
                                                value=val
                                            ))
                                        end
                                    elseif ndims(var_array) == 1
                                        # Scalar or 1D array variables (no time dimension)
                                        for (idx, val) in enumerate(var_array)
                                            if isa(val, AbstractArray)
                                                push!(results_df, (
                                                    technology="index_$idx",
                                                    time_period_idx=missing,
                                                    time_period=missing,
                                                    value=sum(JuMP.value.(val))
                                                ))
                                            else
                                                push!(results_df, (
                                                    technology="index_$idx",
                                                    time_period_idx=missing,
                                                    time_period=missing,
                                                    value=JuMP.value(val)
                                                ))
                                            end
                                        end
                                    else
                                        # Scalar variable
                                        push!(results_df, (
                                            technology="scalar",
                                            time_period_idx=missing,
                                            time_period=missing,
                                            value=JuMP.value(var_array)
                                        ))
                                    end
                                catch
                                    # Skip variables that can't be processed
                                    continue
                                end
                            end
                        end
                    end
                end
            elseif hasfield(typeof(model), :JuMPmodel)
                # Try to extract from JuMP model directly
                jmodel = model.JuMPmodel
                if !isnothing(jmodel)
                    for var_ref in all_variables(jmodel)
                        try
                            push!(results_df, (
                                technology=string(var_ref),
                                time_period_idx=missing,
                                time_period=missing,
                                value=value(var_ref),
                            ))
                        catch
                            continue
                        end
                    end
                end
            end
        end
    catch e
        @warn "Error reading variable: $e"
    end

    return results_df
end

"""
    read_optimization_status(res::OptimizationProblemResults) -> String

Returns solver status as string: "OPTIMAL", "FEASIBLE", "INFEASIBLE", etc.
"""
function read_optimization_status(res::ISOPT.OptimizationProblemResults)
    try
        # Access path: res.model.internal.container.JuMPmodel
        if hasfield(typeof(res), :model)
            model = res.model
            if hasfield(typeof(model), :internal)
                internal = model.internal
                if hasfield(typeof(internal), :container)
                    container = internal.container
                    if hasfield(typeof(container), :JuMPmodel)
                        jmodel = container.JuMPmodel
                        if !isnothing(jmodel)
                            status = termination_status(jmodel)
                            return string(status)
                        end
                    end
                end
            end
        end
    catch e
        @warn "Could not extract optimization status: $e"
    end
    return "UNKNOWN"
end

"""
    extract_investment_summary(res::OptimizationProblemResults, portfolio) -> Dict

Extracts key investment decisions from results:
- Built capacity for each candidate technology
- Total annualized cost
- Optimization status

Returns Dict with structure:
```julia
Dict(
    "Solar_City" => 5.2,  # MW
    "Wind_Expansion" => 7.8,
    "Battery_Power" => 3.5,  # MW
    "Battery_Energy" => 14.0,  # MWh
    "objective_value" => 23.4e6,  # dollars per year
    "status" => "OPTIMAL",
)
```
"""
function extract_investment_summary(res::ISOPT.OptimizationProblemResults, _portfolio)
    summary = Dict(
        "objective_value" => get_objective_value(res),
        "status" => read_optimization_status(res),
        "technologies" => Dict(),
    )

    # Extract all available variables from the container
    try
        var_df = read_variable(res, nothing)
        if !isempty(var_df)
            for row in eachrow(var_df)
                tech_name = row.technology
                value = row.value
                # Store if value is positive (capacity was built)
                if value > 0.01
                    summary["technologies"][tech_name] = value
                end
            end
        end
    catch e
        @warn "Error extracting investment summary: $e"
    end

    return summary
end

"""
    print_results_summary(res::OptimizationProblemResults, portfolio, scenario::Symbol)

Prints formatted results summary to console.
"""
function print_results_summary(res::ISOPT.OptimizationProblemResults, portfolio, scenario::Symbol)
    summary = extract_investment_summary(res, portfolio)

    println("\n" * "="^70)
    println("Kodiak Investment Optimization Results (scenario: $scenario)")
    println("="^70 * "\n")

    println("Optimization Status: $(summary["status"])")
    println("Total Annualized System Cost: \$$(round(summary["objective_value"]/1e6, digits=2))M/yr\n")

    if !isempty(summary["technologies"])
        println("Recommended New Capacity:")
        for (tech, cap) in summary["technologies"]
            if cap > 0.01
                if occursin("Energy", tech)
                    println("  $tech: $(round(cap, digits=2)) MWh")
                else
                    println("  $tech: $(round(cap, digits=2)) MW")
                end
            end
        end
    else
        println("(No investment decisions extracted yet - awaiting full API implementation)")
    end

    println("\n" * "="^70 * "\n")
end
