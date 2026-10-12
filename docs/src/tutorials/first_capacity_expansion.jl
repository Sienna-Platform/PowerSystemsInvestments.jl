# # Build and Solve a Capacity Expansion Model

# In this tutorial, we will plan new generation for a small power system. We will describe
# two candidate technologies and a growing demand in a `Portfolio`, choose how to model them
# in an [`InvestmentModelTemplate`](@ref), and then build and solve an
# [`InvestmentModel`](@ref) to find the least-cost capacity to build in 2030 and in 2035.

# ## Setup

# To get started, ensure you have followed the
# [installation instructions](https://sienna-platform.github.io/Sienna/SiennaDocs/docs/build/how-to/install/).

# Load `PowerSystemsInvestments.jl`, along with
# [`PowerSystemsInvestmentsPortfolios.jl`](https://sienna-platform.github.io/PowerSystemsInvestmentsPortfolios.jl/stable/)
# to define the data and
# [`PowerSystems.jl`](https://sienna-platform.github.io/PowerSystems.jl/stable/) for the
# component types and cost curves:

using PowerSystemsInvestments
using PowerSystemsInvestmentsPortfolios
using PowerSystems

# We will also use `Dates` and
# [`TimeSeries.jl`](https://juliastats.org/TimeSeries.jl/stable/) to define time series
# data, and the open-source solver [`HiGHS.jl`](https://github.com/jump-dev/HiGHS.jl) to
# solve the model:

using Dates
using TimeSeries
using HiGHS

# Some functions we need are not exported, so we define short names for the two packages:

const PSINV = PowerSystemsInvestments
const PSIP = PowerSystemsInvestmentsPortfolios

# ## Describing the Planning Problem with a `Portfolio`

# A `Portfolio` holds all of the data of the planning problem. We start by creating an
# empty one with its financial assumptions: costs are reported in 2025 dollars, with a 7%
# discount rate, 5% inflation rate, and 4% interest rate.

portfolio = Portfolio(2025, 0.07, 0.05, 0.04)

# Every technology is located in a region. Our system is small enough to treat as a single
# zone, so let's create one and add it to the `Portfolio`:

zone = Zone(; name="Zone_1")
add_region!(portfolio, zone)

# ### Adding Candidate Technologies

# Each candidate technology needs the financial terms it would be built under, which are
# used to turn its capital cost into yearly payments. We will use the same terms for both
# of our candidates:

financials = TechnologyFinancialData(;
    capital_recovery_period=30,
    technology_base_year=2025,
    debt_fraction=0.6,
    debt_rate=0.04,
    return_on_equity=0.10,
    tax_rate=0.21,
)

# Our first candidate is a natural gas combined cycle plant. It costs \$1,200,000 per MW to
# build and \$35 per MWh to run, and we allow up to 2,000 MW to be built:

gas = SupplyTechnology{ThermalStandard}(;
    name="gas_cc",
    power_systems_type="ThermalStandard",
    available=true,
    region=[zone],
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

# Notice the type parameter `ThermalStandard`. It tells `PowerSystemsInvestments.jl` which
# kind of generator this technology is, which determines how it can be modeled.

# Our second candidate is a wind plant, which is more expensive to build at \$1,500,000 per
# MW but free to run:

wind = SupplyTechnology{RenewableDispatch}(;
    name="wind",
    power_systems_type="RenewableDispatch",
    available=true,
    region=[zone],
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

# Finally, we need the demand that these technologies must serve:

demand = DemandRequirement{PowerLoad}(;
    name="demand",
    power_systems_type="PowerLoad",
    available=true,
    region=[zone],
)

# Let's add all three to the `Portfolio`:

add_technology!(portfolio, gas)
add_technology!(portfolio, wind)
add_technology!(portfolio, demand)

# ### Adding Time Series

# We will not simulate every hour of the next 15 years. Instead, we will represent the
# operation of the system with one representative day in 2030 and one in 2035. Let's define
# the hourly time stamps of those two days:

day_2030 = collect(DateTime(2030, 1, 1, 0):Hour(1):DateTime(2030, 1, 1, 23));
day_2035 = collect(DateTime(2035, 1, 1, 0):Hour(1):DateTime(2035, 1, 1, 23));

# Next, we define an hourly demand shape that is lowest overnight and peaks in the evening,
# as a fraction of the peak demand:

demand_shape = [0.6 + 0.4 * sin(pi * (hour - 6) / 24)^2 for hour in 0:23]

# We also define the hourly capacity factor of the wind plant, which is the fraction of its
# installed capacity that it can produce in each hour:

wind_capacity_factor = [0.35 + 0.2 * cos(2 * pi * hour / 24) for hour in 0:23]

# Now we can attach the demand to the `Portfolio`, in MW, with a peak of 500 MW in 2030.
# The name `"ops_demand"` is the name `PowerSystemsInvestments.jl` looks for on a demand
# technology. The `features` identify which representative day the data belongs to: the
# `"year"` it is in, and `"rep_day"`, which is its position in the list of representative
# days that we will define later.

demand_2030 = SingleTimeSeries("ops_demand", TimeArray(day_2030, 500.0 .* demand_shape));
PSIP.add_time_series!(
    portfolio,
    demand,
    demand_2030;
    features=Dict("year" => "2030", "rep_day" => 1),
)

# Demand grows to a peak of 650 MW in 2035, our second representative day:

demand_2035 = SingleTimeSeries("ops_demand", TimeArray(day_2035, 650.0 .* demand_shape));
PSIP.add_time_series!(
    portfolio,
    demand,
    demand_2035;
    features=Dict("year" => "2035", "rep_day" => 2),
)

# The wind capacity factor is attached the same way, with the name
# `"ops_variable_cap_factor"`. We will use the same wind shape for both days:

wind_2030 =
    SingleTimeSeries("ops_variable_cap_factor", TimeArray(day_2030, wind_capacity_factor));
wind_2035 =
    SingleTimeSeries("ops_variable_cap_factor", TimeArray(day_2035, wind_capacity_factor));
PSIP.add_time_series!(
    portfolio,
    wind,
    wind_2030;
    features=Dict("year" => "2030", "rep_day" => 1),
)
PSIP.add_time_series!(
    portfolio,
    wind,
    wind_2035;
    features=Dict("year" => "2035", "rep_day" => 2),
)

# The gas plant can always produce up to its installed capacity, so it does not need a time
# series. Our `Portfolio` is complete.

# ## Choosing How to Model the Problem with a Template

# The `Portfolio` says *what* could be built. An [`InvestmentModelTemplate`](@ref) says
# *how* to model it. We will define its four parts one at a time.

# ### Investment Periods

# First, we define when capacity can be built. We will use two investment periods of five
# years each, with a [`DiscountedCashFlow`](@ref) model to account for capital costs:

investment_periods =
    [(Date(2030, 1, 1), Date(2034, 12, 31)), (Date(2035, 1, 1), Date(2039, 12, 31))]
capital = DiscountedCashFlow(0.07, Year(2025), investment_periods)

# ### Operational Periods

# Second, we define how the operation of the system is represented in each investment
# period, using [`OperationalRepresentativeDays`](@ref). Our two representative days go in
# a list, in the same order as the `"rep_day"` values we used for the time series.

# Each day also gets a weight, which is how many real days it stands for. Each of our days
# represents every day of a five-year investment period:

weights = [365.0 * 5, 365.0 * 5]
operations = OperationalRepresentativeDays([day_2030, day_2035], weights)

# ### Feasibility Periods

# Third, a template needs a feasibility model. We will not use feasibility periods in this
# tutorial, so we define a [`RepresentativePeriods`](@ref) model with no periods:

feasibility = RepresentativePeriods(Vector{Vector{DateTime}}())

# ### Energy Balance

# Fourth, we choose how supply and demand are balanced. We have a single zone, so we use a
# [`TransportModel`](@ref) with a [`SingleRegionBalanceModel`](@ref):

transport = TransportModel(SingleRegionBalanceModel)

# Now we can create the template:

template = InvestmentModelTemplate(capital, operations, feasibility, transport)

# ### Technology Formulations

# The last step is to choose a formulation for each technology with
# [`set_technology_model!`](@ref). Each technology gets three formulations: one for its
# investment decision, one for its operation, and one for the feasibility periods.

# Let's start with the gas plant. We let the model build any amount of capacity with
# [`ContinuousInvestment`](@ref), and dispatch it up to its installed capacity with
# [`BasicDispatch`](@ref):

set_technology_model!(
    template,
    ["gas_cc"],
    SupplyTechnology{ThermalStandard},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)

# We use the same formulations for the wind plant. Because it is a `RenewableDispatch`
# technology, [`BasicDispatch`](@ref) will also limit its output with the capacity factor
# time series:

set_technology_model!(
    template,
    ["wind"],
    SupplyTechnology{RenewableDispatch},
    ContinuousInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)

# Demand is not a decision, so it uses [`StaticLoadInvestment`](@ref):

set_technology_model!(
    template,
    ["demand"],
    DemandRequirement{PowerLoad},
    StaticLoadInvestment,
    BasicDispatch,
    BasicDispatchFeasibility,
)

# Let's take a look at the finished template:

template

# ## Building and Solving the Model

# We now combine the template and the `Portfolio` in an [`InvestmentModel`](@ref).
# [`SingleInstanceSolve`](@ref) means the whole problem is solved as one optimization
# problem. We also pass the solver, and choose not to save a copy of the `Portfolio` with
# the results:

model = InvestmentModel(
    template,
    SingleInstanceSolve,
    portfolio;
    optimizer=HiGHS.Optimizer,
    portfolio_to_file=false,
)

# Next, we [`build!`](@ref) the optimization problem. This needs a directory for the log
# file and the results; we will use a temporary one:

output_dir = mktempdir()
build!(model; output_dir=output_dir)

# The model is built. Now let's [`solve!`](@ref) it:

solve!(model)

# !!! tip
#     [`build!`](@ref) and [`solve!`](@ref) return a status instead of throwing an error if
#     something goes wrong. If you do not see `BUILT` and `SUCCESSFULLY_FINALIZED`, look at
#     the file `investment_problem.log` in the output directory.

# ## Looking at the Results

# Results are read by key. A key identifies a variable or expression by its type, the type
# of technology it belongs to, and the formulation that created it. Let's see the keys of
# the variables in our model:

collect(PSINV.list_variable_keys(model))

# ### Capacity Built

# First, how much gas capacity did the model decide to build? We define the key for the
# [`BuildCapacity`](@ref) variable of our gas technology and read it with
# [`read_variable`](@ref):

gas_build_key = PSINV.VariableKey(
    BuildCapacity,
    SupplyTechnology{ThermalStandard},
    "ContinuousInvestment",
)
read_variable(model, gas_build_key)

# There is one row for each investment period: `time_index` 1 is the 2030-2034 period and
# `time_index` 2 is the 2035-2039 period. The `value` is the capacity built in that period,
# in MW.

# Let's do the same for wind:

wind_build_key = PSINV.VariableKey(
    BuildCapacity,
    SupplyTechnology{RenewableDispatch},
    "ContinuousInvestment",
)
read_variable(model, wind_build_key)

# ### Installed Capacity

# [`BuildCapacity`](@ref) is the capacity *added* in each period. The total capacity
# installed by the end of each period is the [`CumulativeCapacity`](@ref) expression, which
# we read with [`read_expression`](@ref):

gas_capacity_key = PSINV.ExpressionKey(
    CumulativeCapacity,
    SupplyTechnology{ThermalStandard},
    "ContinuousInvestment",
)
read_expression(model, gas_capacity_key)

# ### Dispatch

# Finally, let's look at how the gas plant is operated. Its dispatch is the
# [`ActivePowerVariable`](@ref), created by the [`BasicDispatch`](@ref) formulation:

gas_dispatch_key = PSINV.VariableKey(
    ActivePowerVariable,
    SupplyTechnology{ThermalStandard},
    "BasicDispatch",
)
gas_dispatch = read_variable(model, gas_dispatch_key)

# This time, `time_index` counts the hours of our representative days: 1 to 24 are the
# hours of the 2030 day and 25 to 48 are the hours of the 2035 day. The `value` is the
# dispatch in MW.

# ## Next Steps

# In this tutorial, you defined a `Portfolio` with two candidate technologies and a demand,
# chose how to model them with an [`InvestmentModelTemplate`](@ref), and built and solved an
# [`InvestmentModel`](@ref) to find the capacity to build in two investment periods.

# Next, you might want to:

#   - Continue with the next tutorial, [Add Storage, Regions, and Transmission](@ref)
#   - Learn [how the template's formulations fit together](@ref formulation_axes)
#   - Learn [how time is represented](@ref time_representation) in an investment model
#   - See the equations behind [`BasicDispatch`](@ref) in the
#     [Formulation Library](@ref formulation_library_intro)
