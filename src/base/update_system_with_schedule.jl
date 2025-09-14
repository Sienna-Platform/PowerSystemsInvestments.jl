############## Populate System with Schedule Results #################

"""
    get_previous_period_range_keys(
        results::Dict,
        period_range::Tuple{Dates.Date, Dates.Date}
    )

Retrieve all investment period keys from results that start on or before the specified period.

This function is used to identify all previous investment periods that need to be
considered when calculating cumulative capacity investments up to a given period.

# Arguments

  - `results::Dict`: Dictionary containing investment results keyed by period ranges
  - `period_range::Tuple{Dates.Date, Dates.Date}`: Target period range (start_date, end_date)

# Returns

  - `Vector{Tuple{Dates.Date, Dates.Date}}`: Vector of period range keys for all previous periods

# Example

```julia
results = Dict(
    (Date(2025, 1, 1), Date(2029, 12, 31)) => {...},
    (Date(2030, 1, 1), Date(2034, 12, 31)) => {...},
)
target_period = (Date(2030, 1, 1), Date(2034, 12, 31))
previous_periods = get_previous_period_range_keys(results, target_period)
# Returns both periods since 2025 and 2030 start dates are <= 2030
```
"""
function get_previous_period_range_keys(
    results::Dict,
    period_range::Tuple{Dates.Date, Dates.Date},
)
    # Initialize vector to store previous period ranges
    previous_years = Vector{Tuple{Dates.Date, Dates.Date}}()

    # Iterate through all period keys in the results dictionary
    for period_range_key in keys(results)
        # Check if this period starts on or before the target period start date
        if period_range_key[1] <= period_range[1]
            push!(previous_years, period_range_key)
        end
    end

    return previous_years
end

"""
    get_cumulative_build_capacity_results(
        results::Dict,
        tech_type::Type{T},
        tech_name::String,
        period_range::Tuple{Dates.Date, Dates.Date}
    ) where {T <: Union{PSIP.SupplyTechnology, PSIP.AggregateTransportTechnology}}

Calculate the cumulative build capacity for a specific technology across all previous periods.

This function sums up all capacity investments for a given technology from the beginning
of the planning horizon up to and including the specified period. This is essential for
understanding the total installed capacity at any point in time.

# Arguments

  - `results::Dict`: Dictionary containing investment results for all periods
  - `tech_type::Type{T}`: Technology type (SupplyTechnology or AggregateTransportTechnology)
  - `tech_name::String`: Name of the specific technology instance
  - `period_range::Tuple{Dates.Date, Dates.Date}`: Target period to calculate cumulative capacity for

# Returns

  - `Float64`: Total cumulative capacity built up to and including the specified period

# Example

```julia
cumulative_cap = get_cumulative_build_capacity_results(
    results,
    SupplyTechnology,
    "Coal_Plant_1",
    (Date(2030, 1, 1), Date(2034, 12, 31)),
)
# Returns total capacity built in all periods up to 2030-2034
```
"""
function get_cumulative_build_capacity_results(
    results::Dict,
    tech_type::Type{T},
    tech_name::String,
    period_range::Tuple{Dates.Date, Dates.Date},
) where {T <: Union{PSIP.SupplyTechnology, PSIP.AggregateTransportTechnology}}

    # Get all period ranges that occurred on or before the target period
    previous_years = get_previous_period_range_keys(results, period_range)

    # Initialize cumulative capacity counter
    cumulative_capacity = 0.0

    # Sum up the capacities from all previous periods (including current)
    for prev_year in previous_years
        # Get investment results for this specific period
        tech_results = results[prev_year]

        # Add capacity for this technology in this period (0.0 if not found)
        cumulative_capacity += get(tech_results, (tech_type, tech_name), 0.0)
    end

    return cumulative_capacity
end

"""
    read_cumulative_investment_schedule(
        schedule::PSIP.InvestmentScheduleResults,
        period_range::Tuple{Dates.Date, Dates.Date}
    )

Extract cumulative investment results for all technologies up to a specified period.

This function processes an investment schedule and calculates the total cumulative
capacity for each technology from the beginning of the planning horizon up to and
including the specified period. This is used to determine the system configuration
at any point in the investment timeline.

# Arguments

  - `schedule::PSIP.InvestmentScheduleResults`: Complete investment schedule results
  - `period_range::Tuple{Dates.Date, Dates.Date}`: Target period to calculate cumulative results for

# Returns

  - `Dict`: Dictionary mapping (tech_type, tech_name) tuples to cumulative capacity values

# Throws

  - `error`: If no investment results are found for the specified period

# Example

```julia
cumulative_results =
    read_cumulative_investment_schedule(schedule, (Date(2030, 1, 1), Date(2034, 12, 31)))
# Returns: Dict((SupplyTechnology, "Coal_Plant_1") => 500.0, ...)
```
"""
function read_cumulative_investment_schedule(
    schedule::PSIP.InvestmentScheduleResults,
    period_range::Tuple{Dates.Date, Dates.Date},
)
    # Extract the complete results dictionary from the schedule
    results = schedule.results

    # Get investment results for the specific target period
    period_results = get(results, period_range, nothing)
    if isnothing(period_results)
        error("No investment results found for period $period_range")
    end

    # Initialize dictionary to store cumulative results
    cumulative_results = Dict()

    # Calculate cumulative capacity for each technology found in the target period
    for ((tech_type, tech_name), capacity) in period_results
        # Calculate total cumulative capacity from all previous periods
        cumulative_data = get_cumulative_build_capacity_results(
            results,
            tech_type,
            tech_name,
            period_range,
        )
        cumulative_results[(tech_type, tech_name)] = cumulative_data
    end

    return cumulative_results
end

"""
    find_substring_in_vector(name::AbstractString, list_of_techs::Vector{<:AbstractString})

Find the first element in a vector that appears as a substring in the given string.

This utility function is used to match technology names with their corresponding types
by finding which technology type string appears within a technology's full name.
This is helpful for mapping detailed technology names to broader technology categories.

# Arguments

  - `name::AbstractString`: The string to search within (e.g., technology name)
  - `list_of_techs::Vector{<:AbstractString}`: Vector of strings to search for as substrings

# Returns

  - `String` or `nothing`: The first matching substring from the vector, or nothing if no match

# Example

```julia
tech_name = "Coal_Plant_Unit_1"
tech_types = ["Coal", "Gas", "Nuclear"]
result = find_substring_in_vector(tech_name, tech_types)
# Returns: "Coal"
```    # Iterate through each potential technology type
"""
function find_substring_in_vector(
    name::AbstractString,
    list_of_techs::Vector{<:AbstractString},
)
    # Iterate through each potential technology type
    for s in list_of_techs
        # Check if this technology type appears as a substring in the name
        occursin(s, name) && return s
    end

    # Return nothing if no matching substring is found
    return nothing
end

"""
    update_system_with_tech_result!(
        new_sys::PSY.System,
        tech::PSIP.SupplyTechnology{T},
        capacity::Float64
    ) where {T <: PSY.ThermalStandard}

Update a PowerSystems.jl system by adding or modifying thermal generation capacity.

This method handles the integration of thermal technology investment results into a
PowerSystems.jl system. It either creates new thermal generators or updates existing
ones based on the investment schedule results.

# Arguments

  - `new_sys::PSY.System`: PowerSystems.jl system to be updated
  - `tech::PSIP.SupplyTechnology{T}`: Investment technology specification
  - `capacity::Float64`: Capacity to add/update in MW

# Side Effects

  - Modifies `new_sys` by adding new thermal generators
  - Logs information when creating new components

# Notes

  - Currently only supports creating new generators (updating existing ones is TODO)
  - Requires `zonal_to_nodal` and `list_of_techs` mappings in system extensions
  - Uses base power of 100 MVA for per-unit calculations

# Example

```julia
update_system_with_tech_result!(system, thermal_tech, 500.0)
# Adds a 500 MW thermal generator to the system
```
"""
function update_system_with_tech_result!(
    new_sys::PSY.System,
    tech::PSIP.SupplyTechnology{T},
    capacity::Float64,
) where {T <: PSY.ThermalStandard}
    # Extract technology name from the investment technology
    tech_name = PSIP.get_name(tech)

    # TODO: Implement proper zonal to nodal mapping
    # Get mapping from zonal areas and technology types to specific buses
    zonal_to_nodal = new_sys.internal.ext["zonal_to_nodal"]

    # TODO: Implement proper list of technologies
    # Get list of technology type strings for substring matching
    list_of_techs = new_sys.internal.ext["list_of_techs"]

    # Check if a generator with this name already exists in the system
    gen = PSY.get_component(T, new_sys, tech_name)

    if isnothing(gen)
        # Generator doesn't exist, create a new one
        @info "Generator $tech_name of type $T not found in original system. Creating new component"

        # Get the area/region name for this technology
        area_name = PSIP.get_name(only(PSIP.get_region(tech)))

        # Find which technology type this generator belongs to
        tech_type = find_substring_in_vector(tech_name, list_of_techs)

        # Get the specific bus where this generator should be connected
        bus = PSY.get_component(PSY.ACBus, new_sys, zonal_to_nodal[(area_name, tech_type)])

        # Set base power for per-unit calculations
        base_power = 100.0
        cap_pu = capacity / base_power  # Convert to per-unit

        # Create new thermal generator with investment specifications
        new_gen = PSY.ThermalStandard(;
            name=tech_name,
            available=true,
            status=false,  # Start offline
            bus=bus,
            active_power=0.0,  # Initial power output
            reactive_power=0.0,  # Initial reactive power
            rating=cap_pu,  # Maximum capacity in per-unit
            active_power_limits=(min=0.0, max=cap_pu),
            reactive_power_limits=(min=-cap_pu, max=cap_pu),
            ramp_limits=nothing,  # No ramp limits specified
            operation_cost=PSIP.get_operation_costs(tech),
            base_power=base_power,
            prime_mover_type=PSIP.get_prime_mover_type(tech),
            fuel=only(PSIP.get_fuel(tech)),
        )

        # Add the new generator to the system
        PSY.add_component!(new_sys, new_gen)
    else
        # Generator already exists - updating capacity is not yet implemented
        error("TODO: Method for update existing unit")
    end
end

"""
    update_system_with_tech_result!(
        new_sys::PSY.System,
        tech::PSIP.SupplyTechnology{T},
        capacity::Float64
    ) where {T <: PSY.RenewableDispatch}

Update a PowerSystems.jl system by adding or modifying renewable generation capacity.

This method handles the integration of renewable technology investment results into a
PowerSystems.jl system. It either creates new renewable generators or updates existing
ones based on the investment schedule results.

# Arguments

  - `new_sys::PSY.System`: PowerSystems.jl system to be updated
  - `tech::PSIP.SupplyTechnology{T}`: Investment technology specification for renewable generators
  - `capacity::Float64`: Capacity to add/update in MW

# Side Effects

  - Modifies `new_sys` by adding new renewable generators
  - Logs information when creating new components

# Notes

  - Currently only supports creating new generators (updating existing ones is TODO)
  - Requires `zonal_to_nodal` and `list_of_techs` mappings in system extensions
  - Uses base power of 100 MVA for per-unit calculations
  - No ramp limits or minimum up/down times for renewable generators

# Example

```julia
update_system_with_tech_result!(system, wind_tech, 300.0)
# Adds a 300 MW wind generator to the system
```
"""
function update_system_with_tech_result!(
    new_sys::PSY.System,
    tech::PSIP.SupplyTechnology{T},
    capacity::Float64,
) where {T <: PSY.RenewableDispatch}
    # Extract technology name from the investment technology
    tech_name = PSIP.get_name(tech)

    # TODO: Implement proper zonal to nodal mapping
    # Get mapping from zonal areas and technology types to specific buses
    zonal_to_nodal = new_sys.internal.ext["zonal_to_nodal"]

    # TODO: Implement proper list of technologies
    # Get list of technology type strings for substring matching
    list_of_techs = new_sys.internal.ext["list_of_techs"]

    # Check if a generator with this name already exists in the system
    gen = PSY.get_component(T, new_sys, tech_name)

    if isnothing(gen)
        # Generator doesn't exist, create a new one
        @info "Generator $tech_name of type $T not found in original system. Creating new component"

        # Get the area/region name for this technology
        area_name = PSIP.get_name(only(PSIP.get_region(tech)))

        # Find which technology type this generator belongs to
        tech_type = find_substring_in_vector(tech_name, list_of_techs)

        # Get the specific bus where this generator should be connected
        bus = PSY.get_component(PSY.ACBus, new_sys, zonal_to_nodal[(area_name, tech_type)])

        # Set base power for per-unit calculations
        base_power = 100.0
        cap_pu = capacity / base_power  # Convert to per-unit

        # Create new renewable generator with investment specifications
        new_gen = PSY.RenewableDispatch(;
            name=tech_name,
            available=true,
            status=false,  # Start offline
            bus=bus,
            active_power=0.0,  # Initial power output
            reactive_power=0.0,  # Initial reactive power
            rating=cap_pu,  # Maximum capacity in per-unit
            reactive_power_limits=(min=-cap_pu, max=cap_pu),
            operation_cost=PSIP.get_operation_costs(tech),
            base_power=base_power,
            prime_mover_type=PSIP.get_prime_mover_type(tech),
        )

        # Add the new generator to the system
        PSY.add_component!(new_sys, new_gen)
    else
        # Generator already exists - updating capacity is not yet implemented
        error("TODO: Method for update existing unit")
    end
end

"""
    update_system_with_tech_result!(
        new_sys::PSY.System,
        tech::PSIP.AggregateTransportTechnology{T},
        capacity::Float64
    ) where {T <: PSY.ACBranch}

Update a PowerSystems.jl system by adding or modifying transmission line capacity.

This method handles the integration of transmission technology investment results into a
PowerSystems.jl system. It either creates new transmission lines or updates existing
ones based on the investment schedule results.

# Arguments

  - `new_sys::PSY.System`: PowerSystems.jl system to be updated
  - `tech::PSIP.NodalACTransportTechnology{T}`: Investment technology specification for zonal transmission lines
  - `capacity::Float64`: Capacity to add/update in MW

# Side Effects

  - Modifies `new_sys` by adding new lines
  - Logs information when creating new components

# Notes

  - Currently only supports creating new lines (updating existing ones is TODO)
  - Requires `zonal_to_nodal` and `list_of_techs` mappings in system extensions
  - Uses base power of 100 MVA for per-unit calculations

# Example

```julia
update_system_with_tech_result!(system, line, 300.0)
# Adds a 300 MW transmission line to the system
```
"""
function update_system_with_tech_result!(
    new_sys::PSY.System,
    tech::PSIP.AggregateTransportTechnology{T},
    capacity::Float64,
) where {T <: PSY.ACBranch}
    # Extract technology name from the investment technology
    tech_name = PSIP.get_name(tech)

    # TODO: Implement proper zonal to nodal mapping
    # Get mapping from zonal areas and technology types to specific buses
    zonal_to_nodal = new_sys.internal.ext["zonal_to_nodal"]

    # Check if a generator with this name already exists in the system
    line = PSY.get_component(T, new_sys, tech_name)

    if isnothing(line)
        # Generator doesn't exist, create a new one
        @info "Component $tech_name of type $T not found in original system. Creating new component"

        # Get the area/region name for this technology
        area_from = PSIP.get_name(PSIP.get_start_region(tech))
        area_to = PSIP.get_name(PSIP.get_end_region(tech))

        # Get the specific buses where this line should be connected
        bus_from = PSY.get_component(PSY.ACBus, new_sys, zonal_to_nodal[(area_from, tech_name)])
        bus_to = PSY.get_component(PSY.ACBus, new_sys, zonal_to_nodal[(area_to, tech_name)])

        # Use buses to get the specific arc for this line
        arc = only(PSY.get_components(x -> ((PSY.get_from(x)==bus_from) & (PSY.get_to(x)==bus_to)) | 
            ((PSY.get_from(x)==bus_to) & (PSY.get_to(x)==bus_from)),
            PSY.Arc, new_sys)
        )

        # Get a transmission line attached to that same arc to get line parameters
        example_line = first(PSY.get_components(x -> PSY.get_arc(x)==arc, PSY.Line, new_sys))

        # Set base power for per-unit calculations
        cap_pu = capacity / PSY.get_base_power(new_sys)  # Convert to per-unit

        # Create new renewable generator with investment specifications
        new_line = PSY.Line(;
            name=tech_name,
            available=true,
            arc=arc,
            active_power_flow=0.0,  # Initial power output
            reactive_power_flow=0.0,  # Initial reactive power
            rating=cap_pu,  # Maximum capacity in per-unit
            r=PSY.get_r(example_line),
            x=PSY.get_x(example_line),
            b=PSY.get_b(example_line),
            g=PSY.get_g(example_line),
            angle_limits=PSY.get_angle_limits(example_line)
        )

        # Add the new generator to the system
        PSY.add_component!(new_sys, new_line)
    else
        # Generator already exists - updating capacity is not yet implemented
        error("TODO: Method for update existing unit")
    end
end

"""
    update_system_with_investment_schedule!(
        p::PSIP.Portfolio,
        schedule::PSIP.InvestmentScheduleResults,
        period_range::Tuple{Dates.Date, Dates.Date}
    )

Create an updated PowerSystems.jl system incorporating cumulative investment results.

This is the main function that transforms an investment portfolio and schedule into
a concrete PowerSystems.jl system representation. It processes all cumulative capacity
investments up to a specified period and creates/updates generators accordingly.

# Arguments

  - `p::PSIP.Portfolio`: Investment portfolio containing base system and technology definitions
  - `schedule::PSIP.InvestmentScheduleResults`: Complete investment schedule with capacity decisions
  - `period_range::Tuple{Dates.Date, Dates.Date}`: Target period to build system configuration for

# Returns

  - `PSY.System`: Updated PowerSystems.jl system with investment results incorporated

# Process Overview

 1. Calculate cumulative capacity investments for all technologies up to the target period
 2. Create a deep copy of the base system from the portfolio
 3. For each technology with positive cumulative capacity:

      + Retrieve the technology specification from the portfolio
      + Update the system by adding/modifying generators based on capacity results
 4. Return the updated system ready for operational analysis

# Example

```julia
# Create system representing state after 2030-2034 investment period
updated_system = update_system_with_investment_schedule!(
    portfolio,
    investment_results,
    (Date(2030, 1, 1), Date(2034, 12, 31)),
)

# System now contains all generators built from planning start through 2034
```
"""
function update_system_with_investment_schedule!(
    p::PSIP.Portfolio,
    schedule::PSIP.InvestmentScheduleResults,
    period_range::Tuple{Dates.Date, Dates.Date},
)
    # Calculate cumulative investment results for all technologies up to target period
    cumulative_results = read_cumulative_investment_schedule(schedule, period_range)

    # Create a deep copy of the base system to avoid modifying the original
    new_sys = deepcopy(p.base_system)

    # Process each technology that has cumulative capacity investments
    for ((tech_type, tech_name), capacity) in cumulative_results
        # Skip technologies with zero or negative capacity
        if capacity <= 0.0
            continue
        end

        # Retrieve the technology specification from the portfolio
        tech = PSIP.get_technology(tech_type, p, tech_name)

        # Update the system with this technology's capacity investment
        update_system_with_tech_result!(new_sys, tech, capacity)
    end

    # Return the updated system with all investment results incorporated
    return new_sys
end
