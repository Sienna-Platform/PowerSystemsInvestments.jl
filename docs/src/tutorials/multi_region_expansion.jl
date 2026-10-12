# # Add Storage, Regions, and Transmission

# In this tutorial, we will plan a system with two zones: a windy northern zone and a
# southern zone where most of the demand is. We will let the model choose between building
# generation close to the demand, building wind in the north with a transmission line to
# bring it south, and building storage to shift energy between hours.

# This tutorial builds on [Build and Solve a Capacity Expansion Model](@ref), which
# introduces the `Portfolio`, the [`InvestmentModelTemplate`](@ref) and the
# [`InvestmentModel`](@ref). We recommend completing it first.

# ## Setup

# Load the same packages as in the first tutorial:

using PowerSystemsInvestments
using PowerSystemsInvestmentsPortfolios
using PowerSystems
using Dates
using TimeSeries
using HiGHS

const PSINV = PowerSystemsInvestments
const PSIP = PowerSystemsInvestmentsPortfolios

# ## Defining the Zones

# We create a `Portfolio` with the same financial assumptions as before, and this time add
# two zones to it:

portfolio = Portfolio(2025, 0.07, 0.05, 0.04)
north = Zone(; name="North")
south = Zone(; name="South")
add_region!(portfolio, north)
add_region!(portfolio, south)

# ## Adding Technologies in Each Zone

# All of our candidate technologies will use the same financial terms:

financials = TechnologyFinancialData(;
    capital_recovery_period=30,
    technology_base_year=2025,
    debt_fraction=0.6,
    debt_rate=0.04,
    return_on_equity=0.10,
    tax_rate=0.21,
)

# ### Generation

# The gas plant can be built in the south, next to the demand:

gas = SupplyTechnology{ThermalStandard}(;
    name="gas_cc",
    power_systems_type="ThermalStandard",
    available=true,
    region=[south],
    prime_mover_type=PrimeMovers.CC,
    fuel=[ThermalFuels.NATURAL_GAS],
    capital_costs=LinearCurve(1_200_000.0),
    operation_costs=ThermalGenerationCost(;
        variable_operation_cost=CostCurve(LinearCurve(35.0)),
        fixed=0.0,
        start_up=0.0,
        shut_down=0.0,
    ),
    capacity_limits=(min=0.0, max=2000.0),
    financial_data=financials,
)
add_technology!(portfolio, gas)

# The wind plant can only be built in the north:

wind = SupplyTechnology{RenewableDispatch}(;
    name="wind",
    power_systems_type="RenewableDispatch",
    available=true,
    region=[north],
    prime_mover_type=PrimeMovers.WT,
    capital_costs=LinearCurve(1_500_000.0),
    operation_costs=ThermalGenerationCost(;
        variable_operation_cost=CostCurve(LinearCurve(0.0)),
        fixed=0.0,
        start_up=0.0,
        shut_down=0.0,
    ),
    capacity_limits=(min=0.0, max=2000.0),
    financial_data=financials,
)
add_technology!(portfolio, wind)

# ### Storage

# Storage is defined with a `StorageTechnology`. Unlike a generator, it has two capacities
# that the model sizes separately: its power capacity in MW, and its energy capacity in
# MWh. Each has its own capital cost and its own limits.

# Let's define a battery in the south that loses 10% of the energy when charging and
# another 10% when discharging:

battery = StorageTechnology{EnergyReservoirStorage}(;
    name="battery",
    power_systems_type="EnergyReservoirStorage",
    available=true,
    region=[south],
    prime_mover_type=PrimeMovers.BA,
    storage_tech=StorageTech.LIB,
    capital_costs_discharge=LinearCurve(300_000.0),
    capital_costs_energy=LinearCurve(250_000.0),
    operation_costs=StorageCost(;
        charge_variable_cost=CostCurve(LinearCurve(0.0)),
        discharge_variable_cost=CostCurve(LinearCurve(0.0)),
        fixed=0.0,
    ),
    capacity_limits_discharge=(min=0.0, max=500.0),
    capacity_limits_energy=(min=0.0, max=2000.0),
    efficiency=(in=0.9, out=0.9),
    financial_data=financials,
)
add_technology!(portfolio, battery)

# ### Transmission

# Energy moves between zones through an `AggregateTransportTechnology`, which connects a
# start region to an end region. Like generation, its capacity is a decision: we allow up
# to 1,000 MW to be built at \$400,000 per MW, and 3% of the energy sent is lost:

line = AggregateTransportTechnology{ACBranch}(;
    name="north_south",
    power_systems_type="ACBranch",
    available=true,
    start_region=north,
    end_region=south,
    capital_costs=LinearCurve(400_000.0),
    capacity_limits=(min=0.0, max=1000.0),
    line_loss=0.03,
    financial_data=financials,
)
add_technology!(portfolio, line)

# ### Demand

# Each zone has its own demand:

demand_north = DemandRequirement{PowerLoad}(;
    name="demand_north",
    power_systems_type="PowerLoad",
    available=true,
    region=[north],
)
add_technology!(portfolio, demand_north)

#-

demand_south = DemandRequirement{PowerLoad}(;
    name="demand_south",
    power_systems_type="PowerLoad",
    available=true,
    region=[south],
)
add_technology!(portfolio, demand_south)

# ## Adding Time Series

# As in the first tutorial, we use one representative day in 2030 and one in 2035:

day_2030 = collect(DateTime(2030, 1, 1, 0):Hour(1):DateTime(2030, 1, 1, 23));
day_2035 = collect(DateTime(2035, 1, 1, 0):Hour(1):DateTime(2035, 1, 1, 23));
representative_days = [day_2030, day_2035];

# We use the same demand shape for both zones, and a wind shape that is strongest at night,
# when demand is low. That mismatch is what gives storage something to do:

demand_shape = [0.6 + 0.4 * sin(pi * (hour - 6) / 24)^2 for hour in 0:23];
wind_capacity_factor = [0.35 + 0.3 * cos(2 * pi * hour / 24) for hour in 0:23];

# The time series for each representative day are attached the same way as before. With
# two zones and two days there are several to add, so we loop over the days. The position
# of each day in `representative_days` is its `"rep_day"`.

# First, the demand in the north, with a peak of 100 MW in both years:

for (rep_day, day) in enumerate(representative_days)
    time_series = SingleTimeSeries("ops_demand", TimeArray(day, 100.0 .* demand_shape))
    features = Dict("year" => string(year(first(day))), "rep_day" => rep_day)
    PSIP.add_time_series!(portfolio, demand_north, time_series; features=features)
end

# Next, the demand in the south, which grows from a peak of 500 MW in 2030 to 650 MW in
# 2035:

south_peaks = [500.0, 650.0]
for (rep_day, day) in enumerate(representative_days)
    time_series =
        SingleTimeSeries("ops_demand", TimeArray(day, south_peaks[rep_day] .* demand_shape))
    features = Dict("year" => string(year(first(day))), "rep_day" => rep_day)
    PSIP.add_time_series!(portfolio, demand_south, time_series; features=features)
end

# And finally the wind capacity factor:

for (rep_day, day) in enumerate(representative_days)
    time_series =
        SingleTimeSeries("ops_variable_cap_factor", TimeArray(day, wind_capacity_factor))
    features = Dict("year" => string(year(first(day))), "rep_day" => rep_day)
    PSIP.add_time_series!(portfolio, wind, time_series; features=features)
end

# The battery and the line do not need time series.

# ## Defining the Template

# The capital, operation and feasibility models are the same as in the first tutorial:

investment_periods =
    [(Date(2030, 1, 1), Date(2034, 12, 31)), (Date(2035, 1, 1), Date(2039, 12, 31))]
capital = DiscountedCashFlow(0.07, Year(2025), investment_periods)
operations = OperationalRepresentativeDays(representative_days, [365.0 * 5, 365.0 * 5])
feasibility = RepresentativePeriods(Vector{Vector{DateTime}}())

# The energy balance is what changes. With a [`MultiRegionBalanceModel`](@ref), supply and
# demand are balanced in each zone separately, and zones can only exchange energy through
# transport technologies:

transport = TransportModel(MultiRegionBalanceModel)
template = InvestmentModelTemplate(capital, operations, feasibility, transport)

# The generation and demand technologies use the same formulations as before. When several
# technologies of the same type share a formulation, we can list them together, as we do
# here for the two demands:

set_technology_model!(
    template,
    ["gas_cc"],
    SupplyTechnology{ThermalStandard},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
set_technology_model!(
    template,
    ["wind"],
    SupplyTechnology{RenewableDispatch},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)
set_technology_model!(
    template,
    ["demand_north", "demand_south"],
    DemandRequirement{PowerLoad},
    StaticLoadInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)

# Storage has its own operations formulations, which track the energy stored from one hour
# to the next. We use [`CyclicalStorageDispatch`](@ref), which treats each representative
# day as a repeating cycle: the battery must end each day with the same energy it started
# with.

set_technology_model!(
    template,
    ["battery"],
    StorageTechnology{EnergyReservoirStorage},
    ContinuousInvestment,
    CyclicalStorageDispatch,
    BasicDispatchFeasibility,
)

# The line uses [`BasicDispatch`](@ref), which for a transport technology limits the flow
# in either direction to its installed capacity:

set_technology_model!(
    template,
    ["north_south"],
    AggregateTransportTechnology{ACBranch},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)

# ## Building and Solving the Model

# We create, build and solve the model as before:

model = InvestmentModel(
    template,
    SingleInstanceSolve,
    portfolio;
    optimizer=HiGHS.Optimizer,
    portfolio_to_file=false,
)
build!(model; output_dir=mktempdir())

#-

solve!(model)

# ## Looking at the Results

# ### Storage Capacity

# The battery has two build variables, so it also has two installed capacities. Let's read
# its installed power capacity, the [`CumulativePowerCapacity`](@ref) expression, in MW:

battery_power_key = PSINV.ExpressionKey(
    CumulativePowerCapacity,
    StorageTechnology{EnergyReservoirStorage},
    "ContinuousInvestment",
)
read_expression(model, battery_power_key)

# And its installed energy capacity, the [`CumulativeEnergyCapacity`](@ref) expression, in
# MWh:

battery_energy_key = PSINV.ExpressionKey(
    CumulativeEnergyCapacity,
    StorageTechnology{EnergyReservoirStorage},
    "ContinuousInvestment",
)
read_expression(model, battery_energy_key)

# Dividing the energy capacity by the power capacity gives the duration of the battery
# that the model chose, in hours.

# ### Transmission Capacity and Flows

# The line's installed capacity is a [`CumulativeCapacity`](@ref) expression, like a
# generator's:

line_capacity_key = PSINV.ExpressionKey(
    CumulativeCapacity,
    AggregateTransportTechnology{ACBranch},
    "ContinuousInvestment",
)
read_expression(model, line_capacity_key)

# The flow on the line in each hour is the [`FlowActivePowerVariable`](@ref). A positive
# value is a flow from the start region to the end region, here from north to south:

line_flow_key = PSINV.VariableKey(
    FlowActivePowerVariable,
    AggregateTransportTechnology{ACBranch},
    "BasicDispatch",
)
read_variable(model, line_flow_key)

# ### Storage Operation

# Finally, let's look at the energy stored in the battery in each hour, the
# [`StateOfChargeVariable`](@ref), in MWh:

battery_energy_stored_key = PSINV.VariableKey(
    StateOfChargeVariable,
    StorageTechnology{EnergyReservoirStorage},
    "CyclicalStorageDispatch",
)
read_variable(model, battery_energy_stored_key)

# ## Next Steps

# In this tutorial, you defined a `Portfolio` with two zones, added storage and
# transmission as investment options, and used a [`MultiRegionBalanceModel`](@ref) to
# balance each zone separately.

# Next, you might want to:

#   - [Model multiple regions and transmission](@ref multi_region_how_to) in your own
#     `Portfolio`
#   - [Add an energy share requirement](@ref energy_share_how_to), such as a renewable
#     portfolio standard
#   - Compare [`CyclicalStorageDispatch`](@ref) and [`ChronologicalStorageDispatch`](@ref)
#     in the [Formulation Library](@ref storage_formulations)
#   - Learn [how costs are accounted for](@ref cost_accounting) in the objective function
