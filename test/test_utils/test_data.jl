using PowerSystems
using PowerSystemsInvestmentsPortfolios
using PowerSystemCaseBuilder
using Statistics
using InfrastructureSystems
using TimeSeries
using Dates
const PSIP = PowerSystemsInvestmentsPortfolios
const IS = InfrastructureSystems

function test_2_zone_portfolio()
    ########################
    #### Financial Data ####
    ########################

    discount_rate = 0.07
    inflation_rate = 0.05
    interest_rate = 0.04
    base_year = 2025
    capital_recovery_period = 20 # years

    sys = build_system(PSITestSystems, "c_sys5_re")
    set_units_base_system!(sys, "NATURAL_UNITS")

    ###################
    ###### Zones ######
    ###################

    z1 = Zone(name="Zone_1", id=1)

    z2 = Zone(name="Zone_2", id=2)

    ###################
    ### Time Series ###
    ###################

    tstamp_2030_ops = collect(
        DateTime("1/1/2030  0:00:00", "d/m/y  H:M:S"):Hour(1):DateTime(
            "1/1/2030  23:00:00",
            "d/m/y  H:M:S",
        ),
    )
    tstamp_2035_ops = collect(
        DateTime("1/1/2035  0:00:00", "d/m/y  H:M:S"):Hour(1):DateTime(
            "1/1/2035  23:00:00",
            "d/m/y  H:M:S",
        ),
    )

    tstamp_ops = vcat(tstamp_2030_ops, tstamp_2035_ops)
    tstamp_inv = [
        DateTime("1/1/2030  0:00:00", "d/m/y  H:M:S"),
        DateTime("1/1/2035  0:00:00", "d/m/y  H:M:S"),
    ]

    ####################
    ##### Thermals #####
    ####################

    thermals = collect(get_components(ThermalStandard, sys))
    var_cost = PSY.get_variable.((get_operation_cost.((thermals))))
    op_cost = PSY.get_proportional_term.(get_value_curve.(var_cost))

    cheap_th_ixs = 2:4
    exp_th_ixs = [1, 5]
    cheap_th_var_cost = mean(op_cost[cheap_th_ixs])
    exp_th_var_cost = mean(op_cost[exp_th_ixs])

    initial_cap_cheap = sum(get_max_active_power.(thermals[cheap_th_ixs]))
    initial_cap_exp = sum(get_max_active_power.(thermals[exp_th_ixs]))

    # From Conservative 2024-ABT CAPEX: year 2030
    coal_igcc_capex = 6937.377 # $/kW
    coal_new_capex = 3823.56 # $/kW

    coal_igcc_capex_2035 = 6869.263 # $/kW
    coal_new_capex_2035 = 3664.307 # $/kW

    ts_th_cheap_inv_capex = SingleTimeSeries(
        "inv_capex",
        TimeArray(tstamp_inv, [1.0, coal_igcc_capex / coal_igcc_capex_2035]),
    )
    ts_th_exp_inv_capex = SingleTimeSeries(
        "inv_capex",
        TimeArray(tstamp_inv, [1.0, coal_new_capex / coal_new_capex_2035]),
    )

    t_th = SupplyTechnology{ThermalStandard}(;
        base_power=1.0, # Natural Units
        prime_mover_type=PrimeMovers.ST,
        capital_costs=LinearCurve(coal_igcc_capex * 1000.0),
        min_capacity=0.0,
        id=1,
        available=true,
        name="cheap_thermal",
        initial_capacity=0.0,#initial_cap_cheap,
        fuel=ThermalFuels.COAL,
        power_systems_type="ThermalStandard",
        balancing_topology="Region",
        operation_costs=ThermalGenerationCost(
            variable=CostCurve(LinearCurve(cheap_th_var_cost)),
            fixed=0.0,
            start_up=0.0,
            shut_down=0.0,
        ),#LinearCurve(0.0),
        max_capacity=1e8,
        outage_factor=0.92,
        region=z1,
        financial_data=TechnologyFinancialData(
            name="cheap_thermal",
            interest_rate=interest_rate,
            capital_recovery_period=capital_recovery_period,
            technology_base_year=base_year,
        ),
    )

    t_th_mid = SupplyTechnology{ThermalStandard}(;
        base_power=1.0, # Natural Units
        prime_mover_type=PrimeMovers.ST,
        capital_costs=LinearCurve(coal_igcc_capex * 1000.0),
        min_capacity=0.0,
        id=1,
        available=true,
        name="mid_thermal",
        initial_capacity=0.0,#initial_cap_cheap,
        fuel=ThermalFuels.COAL,
        power_systems_type="ThermalStandard",
        balancing_topology="Region",
        operation_costs=ThermalGenerationCost(
            variable=CostCurve(LinearCurve(cheap_th_var_cost)),
            fixed=0.0,
            start_up=0.0,
            shut_down=0.0,
        ),#LinearCurve(0.0),
        max_capacity=1e8,
        outage_factor=0.92,
        region=z2,
        financial_data=TechnologyFinancialData(
            name="mid_thermal",
            interest_rate=interest_rate,
            capital_recovery_period=capital_recovery_period,
            technology_base_year=base_year,
        ),
    )

    t_th_exp = SupplyTechnology{ThermalStandard}(;
        base_power=1.0, # Natural Units
        prime_mover_type=PrimeMovers.ST,
        capital_costs=LinearCurve(coal_new_capex * 1000.0),
        min_capacity=0.0,
        id=2,
        available=true,
        name="expensive_thermal",
        initial_capacity=0.0, #initial_cap_exp,
        fuel=ThermalFuels.COAL,
        power_systems_type="ThermalStandard",
        balancing_topology="Region",
        operation_costs=ThermalGenerationCost(
            variable=CostCurve(LinearCurve(exp_th_var_cost)),
            fixed=0.0,
            start_up=0.0,
            shut_down=0.0,
        ),
        max_capacity=1e8,
        outage_factor=0.95,
        region=z1,
        financial_data=TechnologyFinancialData(
            name="expensive_thermal",
            interest_rate=interest_rate,
            capital_recovery_period=capital_recovery_period,
            technology_base_year=base_year,
        ),
    )

    #####################
    ##### Renewable #####
    #####################

    renewables = collect(get_components(RenewableDispatch, sys))
    wind_op_costs =
        get_proportional_term.(
            get_value_curve.(PSY.get_variable.((get_operation_cost.((renewables)))))
        )
    wind_op_cost = mean(wind_op_costs)
    initial_cap_wind = sum(get_max_active_power.(renewables))

    # From Conservative 2024-ABT CAPEX: year 2030 for Wind Class 4 Technology 1
    wind_capex = 1577.392 # $/kW
    wind_capex_2035 = 1522.152 #

    ts_wind_2030 = zeros(length(tstamp_2030_ops))
    ts_wind_2035 = zeros(length(tstamp_2030_ops))
    for gen in renewables
        ts = get_time_series(Deterministic, gen, "max_active_power")
        for (date, data) in ts.data
            for (ix, val) in enumerate(data)
                if date == DateTime("2024-01-01T00:00:00")
                    ts_wind_2030[ix] += val * get_max_active_power(gen)
                else
                    ts_wind_2035[ix] += val * get_max_active_power(gen)
                end
            end
        end
    end
    ts_wind_2030_data = ts_wind_2030 / initial_cap_wind
    ts_wind_2035_data = ts_wind_2035 / initial_cap_wind

    #ts_wind = SingleTimeSeries("ops_variable_cap_factor", TimeArray(tstamp_ops, vcat(ts_wind_2030, ts_wind_2035)))
    ts_wind_2030 = SingleTimeSeries(;
        data=TimeArray(tstamp_2030_ops, ts_wind_2030_data),
        name="ops_variable_cap_factor",
        scaling_factor_multiplier=get_initial_capacity,
    )
    ts_wind_2035 = SingleTimeSeries(;
        data=TimeArray(tstamp_2035_ops, ts_wind_2035_data),
        name="ops_variable_cap_factor",
        scaling_factor_multiplier=get_initial_capacity,
    )

    ts_wind_inv_capex = SingleTimeSeries(
        "inv_capex",
        TimeArray(tstamp_inv, [1.0, wind_capex / wind_capex_2035]),
    )

    t_re = SupplyTechnology{RenewableDispatch}(;
        base_power=1.0, # Natural Units
        prime_mover_type=PrimeMovers.WT,
        capital_costs=LinearCurve(wind_capex * 1000.0), # to $/MW
        min_capacity=0.0,
        id=3,
        available=true,
        name="wind",
        initial_capacity=0.0, #initial_cap_wind,
        fuel=ThermalFuels.OTHER,
        power_systems_type="RenewableDispatch",
        balancing_topology="Region",
        operation_costs=ThermalGenerationCost(
            variable=CostCurve(LinearCurve(0.0)),
            fixed=wind_op_cost,
            start_up=0.0,
            shut_down=0.0,
        ),
        max_capacity=1e8,
        region=z2,
        outage_factor=0.92,
        financial_data=TechnologyFinancialData(
            name="wind",
            interest_rate=interest_rate,
            capital_recovery_period=capital_recovery_period,
            technology_base_year=base_year,
        ),
    )

    ########################
    ######## Storage #######
    ########################

    t_stor = StorageTechnology{EnergyReservoirStorage}(;
        name="test_storage",
        base_power=1.0,
        id=1,
        storage_tech=StorageTech.LIB,
        power_systems_type="EnergyReservoirStorage",
        balancing_topology="Region",
        prime_mover_type=PrimeMovers.BT,
        available=true,
        capital_costs_power=LinearCurve(100000),
        capital_costs_energy=LinearCurve(100000),
        operations_costs_energy=StorageCost(fixed=0.0),
        operations_costs_power=StorageCost(fixed=0.0),
        region=z2,
        financial_data=TechnologyFinancialData(
            name="test_storage",
            interest_rate=interest_rate,
            capital_recovery_period=capital_recovery_period,
            technology_base_year=base_year,
        ),
    )

    #####################
    ######## Load #######
    #####################

    loads = collect(get_components(PowerLoad, sys))
    peak_load = sum(get_active_power.(loads))

    ts_load_2030 = zeros(length(tstamp_2030_ops))
    ts_load_2035 = zeros(length(tstamp_2030_ops))
    for load in loads
        ts = get_time_series(Deterministic, load, "max_active_power")
        for (date, data) in ts.data
            for (ix, val) in enumerate(data)
                if date == DateTime("2024-01-01T00:00:00")
                    ts_load_2030[ix] += val * get_max_active_power(load)
                else
                    ts_load_2035[ix] += val * get_max_active_power(load) * 1.5
                end
            end
        end
    end

    # Data added in MW
    ts_demand_2030 =
        SingleTimeSeries("ops_peak_load", TimeArray(tstamp_2030_ops, ts_load_2030))
    ts_demand_2035 =
        SingleTimeSeries("ops_peak_load", TimeArray(tstamp_2035_ops, ts_load_2035))

    t_demand1 = DemandRequirement{PowerLoad}(
        #load_growth=0.05,
        name="demand1",
        available=true,
        power_systems_type="PowerLoad",
        region=z1,
        #peak_load=peak_load,
    )

    t_demand2 = DemandRequirement{PowerLoad}(
        #load_growth=0.05,
        name="demand2",
        available=true,
        power_systems_type="PowerLoad",
        region=z2,
        #peak_load=peak_load,
    )

    ####################
    ##### Transmission #####
    #####################

    line = ACTransportTechnology{ACBranch}(
        name="test_branch",
        id=1,
        start_region=z1,
        end_region=z2,
        existing_line_capacity=100,
        maximum_new_capacity=900,
        line_loss=0.05,
        capital_cost=LinearCurve(5000.0),
        available=true,
        power_systems_type="TransportTechnology",
        base_power=1.0,
        financial_data=TechnologyFinancialData(
            name="test_branch",
            interest_rate=interest_rate,
            capital_recovery_period=capital_recovery_period,
            technology_base_year=base_year,
        ),
    )

    ####################
    ##### Portfolio #####
    #####################
    p_5bus = Portfolio()
    financial = PortfolioFinancialData(
        name="test_portfolio",
        base_year=base_year,
        discount_rate=discount_rate,
        inflation_rate=inflation_rate,
        interest_rate=interest_rate,
    )
    PSIP.add_financials!(p_5bus, financial)

    PSIP.add_region!(p_5bus, z1)
    PSIP.add_region!(p_5bus, z2)
    PSIP.add_technology!(p_5bus, t_th)
    PSIP.add_technology!(p_5bus, t_re)
    PSIP.add_technology!(p_5bus, t_th_exp)
    PSIP.add_technology!(p_5bus, t_demand1)
    PSIP.add_technology!(p_5bus, t_demand2)
    PSIP.add_technology!(p_5bus, t_stor)
    PSIP.add_technology!(p_5bus, t_th_mid)
    PSIP.add_technology!(p_5bus, line)

    PSIP.add_time_series!(p_5bus, t_th, ts_th_cheap_inv_capex)
    PSIP.add_time_series!(p_5bus, t_th_exp, ts_th_exp_inv_capex)

    IS.add_time_series!(p_5bus.data, t_re, ts_wind_2030; year="2030", rep_day=1)
    IS.add_time_series!(p_5bus.data, t_re, ts_wind_2035; year="2035", rep_day=2)
    PSIP.add_time_series!(p_5bus, t_re, ts_wind_inv_capex)

    IS.add_time_series!(p_5bus.data, t_demand1, ts_demand_2030; year="2030", rep_day=1)
    IS.add_time_series!(p_5bus.data, t_demand1, ts_demand_2035; year="2035", rep_day=2)
    IS.add_time_series!(p_5bus.data, t_demand2, ts_demand_2030; year="2030", rep_day=1)
    IS.add_time_series!(p_5bus.data, t_demand2, ts_demand_2035; year="2035", rep_day=2)
    return p_5bus, [tstamp_2030_ops, tstamp_2035_ops]
end
