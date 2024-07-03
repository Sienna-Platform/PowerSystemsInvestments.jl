using Revise
import InfrastructureSystems
using PowerSystemsInvestmentsPortfolios
using PowerSystemsInvestments
using PowerSystems
using JuMP
using DataStructures
const IS = InfrastructureSystems
const PSIP = PowerSystemsInvestmentsPortfolios
const PSY = PowerSystems
const PSIN = PowerSystemsInvestments

p = Portfolio(0.07)

t_th = SupplyTechnology{ThermalStandard}(;
    base_power=100.0,
    prime_mover_type=PrimeMovers.ST,
    capital_cost=LinearFunctionData(50.0),
    minimum_required_capacity=0.0,
    gen_ID="1",
    available=true,
    name="thermal_tech",
    initial_capacity=200.0,
    fuel=ThermalFuels.COAL,
    power_systems_type="ThermalStandard",
    variable_cost=LinearFunctionData(1.0),
    balancing_topology="Region",
    operations_cost=LinearFunctionData(5.0),
    maximum_capacity=10000.0,
    capacity_factor=0.98,
)

t_th_ext = t_th.ext
t_th_ext["capital_cost"] = OrderedDict(2030 => 50.0, 2040 => 125.0)
t_th_ext["operations_cost"] = OrderedDict(2030 => 5.0, 2040 => 2.5)
t_th_ext["variable_cost"] = OrderedDict(2030 => 1.0, 2040 => 1.0)
t_th_ext["investment_periods"] = [2030, 2040]
# one option is to repeat these for each investment
t_th_ext["operational_periods"] = [1, 2, 3]
t_th_ext["operational_periods_2"] = [
    1,
    2,
    3, # first investment period
    4,
    5,
    6, # second investment period
]
t_th_ext["investment_operational_periods_map"] =
    OrderedDict(1 => 2030, 2 => 2030, 3 => 2030, 4 => 2040, 5 => 2040, 6 => 2040)
t_th_ext["initial_capacity"] = 200.0 # Data in MW
t_th_ext["maximum_capacity"] = 10000.0
t_th_ext["minimum_required_capacity"] = OrderedDict(2030 => 0.0, 2040 => 0.0)

t_th_exp = SupplyTechnology{ThermalStandard}(;
    base_power=100.0,
    prime_mover_type=PrimeMovers.ST,
    capital_cost=LinearFunctionData(150.0),
    minimum_required_capacity=0.0,
    gen_ID="1",
    available=true,
    name="thermal_tech_expensive",
    initial_capacity=200.0,
    fuel=ThermalFuels.WASTE_OIL,
    power_systems_type="ThermalStandard",
    variable_cost=LinearFunctionData(1.0),
    balancing_topology="Region",
    operations_cost=LinearFunctionData(15.0),
    maximum_capacity=10000.0,
    capacity_factor=0.92,
)

t_th_exp_ext = t_th_exp.ext
t_th_exp_ext["capital_cost"] = OrderedDict(2030 => 150.0, 2040 => 100.0)
t_th_exp_ext["operations_cost"] = OrderedDict(2030 => 15.0, 2040 => 10.0)
t_th_exp_ext["variable_cost"] = OrderedDict(2030 => 3.0, 2040 => 2.0)
t_th_exp_ext["investment_periods"] = [2030, 2040]
# one option is to repeat these for each investment
t_th_exp_ext["operational_periods"] = [1, 2, 3]
t_th_exp_ext["operational_periods_2"] = [
    1,
    2,
    3, # first investment period
    4,
    5,
    6,  # second investment period
]

t_th_exp_ext["investment_operational_periods_map"] =
    OrderedDict(1 => 2030, 2 => 2030, 3 => 2030, 4 => 2040, 5 => 2040, 6 => 2040)
t_th_exp_ext["initial_capacity"] = 200.0 # Data in MW
t_th_exp_ext["maximum_capacity"] = 10000.0
t_th_exp_ext["minimum_required_capacity"] = OrderedDict(2030 => 0, 2040 => 0)

# Renewable Technology

t_re = SupplyTechnology{RenewableDispatch}(;
    base_power=100.0,
    prime_mover_type=PrimeMovers.WT,
    capital_cost=LinearFunctionData(100.0),
    minimum_required_capacity=0.0,
    gen_ID="1",
    available=true,
    name="renewable_tech",
    initial_capacity=200.0,
    fuel=ThermalFuels.OTHER,
    power_systems_type="RenewableDispatch",
    variable_cost=LinearFunctionData(0.0),
    balancing_topology="Region",
    operations_cost=LinearFunctionData(10.0),
    maximum_capacity=10000.0,
    capacity_factor=1.0, # There is a variable cap
)

t_re_ext = t_re.ext
t_re_ext["capital_cost"] = OrderedDict(2030 => 100.0, 2040 => 75.0)
t_re_ext["operations_cost"] = OrderedDict(2030 => 10.0, 2040 => 6.5)
t_re_ext["variable_cost"] = OrderedDict(2030 => 0, 2040 => 0)
t_re_ext["variable_capacity_factor"] = [0.8, 0.6, 0.3, 0.5, 0.9, 0.4]
t_re_ext["investment_periods"] = [2030, 2040]
# one option is to repeat these for each investment
t_re_ext["operational_periods"] = [
    1,
    2,
    3, # first investment period
    4,
    5,
    6,  # second investment period
]
t_re_ext["investment_operational_periods_map"] =
    OrderedDict(1 => 2030, 2 => 2030, 3 => 2030, 4 => 2040, 5 => 2040, 6 => 2040)
t_re_ext["initial_capacity"] = 200.0 # Data in MW
t_re_ext["maximum_capacity"] = 10000.0
t_re_ext["minimum_required_capacity"] = OrderedDict(2030 => 0, 2040 => 0)

# Demand side technologies
d_1 = DemandRequirement{ElectricLoad}(
    load_growth=0.05,
    name="demand",
    available=true,
    power_systems_type="ElectricLoad",
    region="1",
    peak_load=100.0,
)

d_1_ext = d_1.ext
d_1_ext["load_scale_factor"] =
    OrderedDict(1 => 1.0, 2 => 1.5, 3 => 1.75, 4 => 0.8, 5 => 3, 6 => 1.2)

temp_container = Dict()
temp_container["components"] =
    Dict(t_th.name => t_th, t_th_exp.name => t_th_exp, t_re.name => t_re, d_1.name => d_1)
temp_container["data"] = Dict()
temp_container["data"]["investment_operational_periods_map"] =
    OrderedDict(1 => 2030, 2 => 2030, 3 => 2030, 4 => 2040, 5 => 2040, 6 => 2040)
temp_container["data"]["operational_periods"] = [1, 2, 3, 4, 5, 6]
temp_container["data"]["investment_periods"] = [2030, 2040]
temp_container["variables"] = Dict()
temp_container["expressions"] = Dict()
temp_container["constraints"] = Dict()

PSIP.add_technology!(p, t_th)
PSIP.add_technology!(p, t_re)
PSIP.add_technology!(p, t_th_exp)
PSIP.add_technology!(p, d_1)

IS.serialize(t_th)
IS.serialize(t_re)
IS.serialize(t_th_exp)
IS.serialize(p)

PSIP.get_technologies(x -> (PSIP.get_available(x)), SupplyTechnology{ThermalStandard}, p)

PSIP.get_technologies(SupplyTechnology{ThermalStandard}, p)
PSIP.remove_technology!(SupplyTechnology{ThermalStandard}, p, "thermal_tech")

#get_available(t_th)
#get_available(t_re)
#get_available(t_th_exp)
#IS.deserialize(p)
