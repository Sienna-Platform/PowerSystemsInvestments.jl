"""
    get_build_capacity_results(
        tech_type::Type{T},
        meta::String,
        variable_values::Dict,
        investment_step::Int,
    ) where {T <: Union{PSIP.SupplyTechnology, PSIP.AggregateTransportTechnology}}

Extract build capacity results for supply and aggregate transport technologies from optimization results.

This method handles technologies that have a single capacity variable (BuildCapacity).

# Arguments

  - `tech_type::Type{T}`: The technology type (SupplyTechnology or AggregateTransportTechnology)
  - `meta::String`: Metadata string identifying the technology formulation
  - `variable_values::Dict`: Dictionary containing all variable results from the optimization
  - `investment_step::Int`: The specific investment time step to extract results for

# Returns

  - `Vector`: Array of [technology_name, capacity_value] pairs for all technologies of this type

# Example

```julia
results = get_build_capacity_results(SupplyTechnology, "ThermalStandard", vars, 1)
# Returns: [["Coal_Plant_1", 100.0], ["Gas_Plant_2", 250.0], ...]
```
"""
function get_build_capacity_results(
    tech_type::Type{T},
    meta::String,
    variable_values::Dict,
    investment_step::Int,
) where {T <: Union{PSIP.SupplyTechnology, PSIP.AggregateTransportTechnology}}
    # Create the variable key to lookup build capacity results
    key = ISOPT.VariableKey{BuildCapacity, T}(meta)

    # Extract the DataFrame containing results for this technology type
    df_res = variable_values[key]

    # Get the names of all technology instances from DataFrame column names
    tech_names = DataFrames.names(df_res)

    # Initialize results array
    res = []

    # Iterate through each technology instance (column) in the DataFrame
    for (ix, col) in enumerate(DataFrames.eachcol(df_res))
        # Extract the capacity value for the specific investment step
        # and pair it with the technology name
        push!(res, [tech_names[ix], col[investment_step]])
    end

    return res
end

"""
    get_build_capacity_results(
        tech_type::Type{T},
        meta::String,
        variable_values::Dict,
        investment_step::Int,
    ) where {T <: PSIP.StorageTechnology}

Extract build capacity results for storage technologies from optimization results.

Storage technologies require both power capacity (MW) and energy capacity (MWh) variables,
so this method extracts and combines both types of capacity results.

# Arguments

  - `tech_type::Type{T}`: The storage technology type
  - `meta::String`: Metadata string identifying the technology formulation
  - `variable_values::Dict`: Dictionary containing all variable results from the optimization
  - `investment_step::Int`: The specific investment time step to extract results for

# Returns

  - `Vector`: Array of [technology_name, (build_p=power_capacity, build_e=energy_capacity)] pairs

# Example

```julia
results = get_build_capacity_results(StorageTechnology, "BatteryEMS", vars, 1)
# Returns: [["Battery_1", (build_p=50.0, build_e=200.0)], ...]
```
"""
function get_build_capacity_results(
    tech_type::Type{T},
    meta::String,
    variable_values::Dict,
    investment_step::Int,
) where {T <: PSIP.StorageTechnology}

    # Extract power capacity results (MW)
    key = ISOPT.VariableKey{BuildPowerCapacity, T}(meta)
    df_res = variable_values[key]
    tech_names = DataFrames.names(df_res)

    # Initialize array to store power capacity results
    res_p = zeros(length(tech_names))
    for (ix, col) in enumerate(DataFrames.eachcol(df_res))
        # Extract power capacity for this investment step
        res_p[ix] = col[investment_step]
    end

    # Extract energy capacity results (MWh)
    key = ISOPT.VariableKey{BuildEnergyCapacity, tech_type}(meta)
    df_res = variable_values[key]

    # Initialize array to store energy capacity results
    res_e = zeros(length(tech_names))
    for (ix, col) in enumerate(DataFrames.eachcol(df_res))
        # Extract energy capacity for this investment step
        res_e[ix] = col[investment_step]
    end

    # Combine power and energy capacity results into named tuples
    return [
        [name, (build_p=res_p[ix], build_e=res_e[ix])] for
        (ix, name) in enumerate(tech_names)
    ]
end

"""
    get_build_capacity_results(
        tech_type::Type{T},
        meta::String,
        variable_values::Dict,
        investment_step::Int,
    ) where {T <: PSIP.ColocatedSupplyStorageTechnology}

Extract build capacity results for colocated supply-storage technologies from optimization results.

Colocated technologies have multiple capacity variables including power, energy, wind, solar,
and inverter capacities. This method extracts all relevant capacity types and combines them
into comprehensive named tuples for each technology instance.

# Arguments

  - `tech_type::Type{T}`: The colocated supply-storage technology type
  - `meta::String`: Metadata string identifying the technology formulation
  - `variable_values::Dict`: Dictionary containing all variable results from the optimization
  - `investment_step::Int`: The specific investment time step to extract results for

# Returns

  - `Vector`: Array of [technology_name, named_tuple_of_capacities] pairs where the named tuple
    contains fields like `build_p`, `build_e`, `build_wind`, `build_solar`, `build_inverter`

# Example

```julia
results =
    get_build_capacity_results(ColocatedSupplyStorageTechnology, "HybridSystem", vars, 1)
# Returns: [["Hybrid_1", (build_p=100.0, build_e=400.0, build_wind=150.0, build_solar=80.0, build_inverter=120.0)], ...]
```
"""
function get_build_capacity_results(
    tech_type::Type{T},
    meta::String,
    variable_values::Dict,
    investment_step::Int,
) where {T <: PSIP.ColocatedSupplyStorageTechnology}

    # Define all variable types that colocated technologies can have
    var_types = [
        BuildPowerCapacity,
        BuildEnergyCapacity,
        BuildWindCapacity,
        BuildSolarCapacity,
        BuildInverterCapacity,
    ]

    # Map variable types to their corresponding named tuple field names
    type_to_named_tuple = Dict(
        BuildPowerCapacity => :build_p,
        BuildEnergyCapacity => :build_e,
        BuildWindCapacity => :build_wind,
        BuildSolarCapacity => :build_solar,
        BuildInverterCapacity => :build_inverter,
    )

    # Temporary dictionary to store results before converting to named tuples
    temp_dict = Dict()

    # Get technology names from the first available variable (BuildPowerCapacity)
    key = ISOPT.VariableKey{BuildPowerCapacity, T}(meta)
    df_res = variable_values[key]
    tech_names = DataFrames.names(df_res)

    # Initialize nested dictionaries for each technology
    for name in tech_names
        temp_dict[name] = Dict()
    end

    # Extract capacity values for each variable type
    for var_type in var_types
        # Create variable key for current capacity type
        key = ISOPT.VariableKey{var_type, T}(meta)
        df_res = variable_values[key]
        tech_names = DataFrames.names(df_res)

        # Extract values for each technology instance
        for (ix, col) in enumerate(DataFrames.eachcol(df_res))
            # Store the capacity value using the appropriate field name
            push!(
                temp_dict[tech_names[ix]],
                type_to_named_tuple[var_type] => col[investment_step],
            )
        end
    end

    # Convert dictionaries to named tuples for each technology
    return [[name, (; (k => v for (k, v) in dict)...)] for (name, dict) in temp_dict]
end

"""
    InvestmentScheduleResults(model::InvestmentModel)

Constructor for InvestmentScheduleResults that extracts and organizes investment capacity
results from a completed optimization model.

This constructor processes the optimization results from an InvestmentModel and organizes
them by investment period and technology type. It handles different types of investment
technologies (supply, storage, transport, and colocated) and extracts the appropriate
capacity variables for each.

# Arguments

  - `model::InvestmentModel`: A completed investment optimization model containing results

# Returns

  - `InvestmentScheduleResults`: Object containing organized investment results by time period
    and technology type

# Process Overview

 1. Extract optimization results and variable values from the model
 2. Identify investment technology formulations from the model
 3. Get investment time periods from the time mapping
 4. For each investment period and technology type, extract capacity results
 5. Organize results in a nested dictionary structure

# Example

```julia
# After solving an investment model
results = InvestmentScheduleResults(investment_model)

# Access results for a specific period and technology
period = (Date("2030-01-01"), Date("2034-12-31"))
coal_capacity = results.results[period][(SupplyTechnology, "Coal_Plant_1")]    # Extract optimization results from the solved model
```
"""
function read_investment_schedule_results(model::InvestmentModel)
    # Extract optimization results from the solved model
    res = OptimizationProblemResults(model)

    # Get the optimization container and time mapping
    container = get_optimization_container(model)
    tmap = get_time_mapping(container)

    # Get list of all available investment technology formulation types
    investment_models_list =
        string.(InteractiveUtils.subtypes(InvestmentTechnologyFormulation))

    # Extract investment time periods (tuples of start and end dates)
    investment_tuples = get_investment_time_stamps(tmap)

    # Get all variable values from the optimization results
    variable_values = ISOPT.get_variable_values(res)
    vars_keys = keys(variable_values)

    # Extract technology types and metadata from variable keys
    tech_types = [(ISOPT.get_component_type(x), x.meta) for x in vars_keys]

    # Filter to only include investment technology formulations
    ixs_to_consider = Int[]
    for (ix, tech_type) in enumerate(deepcopy(tech_types))
        tech = tech_type[1]
        meta = tech_type[2]
        # Check if this technology uses an investment formulation
        if meta ∈ investment_models_list
            push!(ixs_to_consider, ix)
        end
    end

    # Get unique combinations of technology types and formulations for investment technologies
    final_tech_types = unique(tech_types[ixs_to_consider])

    # Initialize results dictionary to store all investment results
    results = Dict()

    # Process results for each investment time period
    for (ix, investment_tuple) in enumerate(investment_tuples)
        # Initialize dictionary to store results for this investment period
        ix_results = Dict()

        # Process each technology type that has investment variables
        for (tech_type, meta) in final_tech_types
            # Extract build capacity results for this technology type and investment step
            capacity_results =
                get_build_capacity_results(tech_type, meta, variable_values, ix)

            # Store results for each individual technology instance
            for (name, capacity_result) in capacity_results
                # Use (technology_type, technology_name) as the key
                ix_results[(tech_type, name)] = capacity_result
            end
        end

        # Store all results for this investment period
        results[investment_tuple] = ix_results
    end

    # Return the complete InvestmentScheduleResults object
    return PSIP.InvestmentScheduleResults(results)
end
