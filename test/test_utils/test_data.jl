using PowerSystems
using PowerSystemsInvestmentsPortfolios
using PowerSystemCaseBuilder
using Statistics
using InfrastructureSystems
using TimeSeries
using Dates
const PSIP = PowerSystemsInvestmentsPortfolios
const IS = InfrastructureSystems

function test_data()
    sys = build_system(PSITestSystems, "c_sys5_re")
    set_units_base_system!(sys, "NATURAL_UNITS")

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
    var_cost = get_variable.((get_operation_cost.((thermals))))
    op_cost = get_proportional_term.(get_value_curve.(var_cost))

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
        capital_cost=LinearCurve(coal_igcc_capex * 1000.0),
        minimum_required_capacity=0.0,
        gen_ID="1",
        available=true,
        name="cheap_thermal",
        initial_capacity=initial_cap_cheap,
        fuel=ThermalFuels.COAL,
        power_systems_type="ThermalStandard",
        variable_cost=LinearCurve(cheap_th_var_cost),
        balancing_topology="Region",
        operations_cost=LinearCurve(0.0),
        maximum_capacity=1e8,
        capacity_factor=0.92,
    )

    t_th_exp = SupplyTechnology{ThermalStandard}(;
        base_power=1.0, # Natural Units
        prime_mover_type=PrimeMovers.ST,
        capital_cost=LinearCurve(coal_new_capex * 1000.0),
        minimum_required_capacity=0.0,
        gen_ID="1",
        available=true,
        name="expensive_thermal",
        initial_capacity=initial_cap_exp,
        fuel=ThermalFuels.COAL,
        power_systems_type="ThermalStandard",
        variable_cost=LinearCurve(exp_th_var_cost),
        balancing_topology="Region",
        operations_cost=LinearCurve(0.0),
        maximum_capacity=1e8,
        capacity_factor=0.95,
    )

    #####################
    ##### Renewable #####
    #####################

    renewables = collect(get_components(RenewableDispatch, sys))
    wind_op_costs =
        get_proportional_term.(
            get_value_curve.(get_variable.((get_operation_cost.((renewables)))))
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
        capital_cost=LinearCurve(wind_capex * 1000.0), # to $/MW
        minimum_required_capacity=0.0,
        gen_ID="1",
        available=true,
        name="wind",
        initial_capacity=initial_cap_wind,
        fuel=ThermalFuels.OTHER,
        power_systems_type="RenewableDispatch",
        variable_cost=LinearCurve(0.0),
        balancing_topology="Region",
        operations_cost=LinearCurve(wind_op_cost),
        maximum_capacity=1e8,
        capacity_factor=0.92,
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
                    ts_load_2035[ix] += val * get_max_active_power(load)
                end
            end
        end
    end
    ts_load_2030 = ts_load_2030 / peak_load
    ts_load_2035 = ts_load_2035 / peak_load

    ts_demand = SingleTimeSeries(
        "ops_peak_load",
        TimeArray(tstamp_ops, vcat(ts_load_2030, ts_load_2035)),
        scaling_factor_multiplier=get_peak_load,
    )
    ts_demand_2030 = SingleTimeSeries(
        "ops_peak_load",
        TimeArray(tstamp_2030_ops, ts_load_2030),
        scaling_factor_multiplier=get_peak_load,
    )
    ts_demand_2035 = SingleTimeSeries(
        "ops_peak_load",
        TimeArray(tstamp_2035_ops, ts_load_2035),
        scaling_factor_multiplier=get_peak_load,
    )

    t_demand = DemandRequirement{PowerLoad}(
        load_growth=0.05,
        name="demand",
        available=true,
        power_systems_type="PowercLoad",
        region="1",
        peak_load=peak_load,
    )

    #####################
    ##### Portfolio #####
    #####################

    discount_rate = 0.07
    p_5bus = Portfolio(discount_rate)

    PSIP.add_technology!(p_5bus, t_th)
    PSIP.add_technology!(p_5bus, t_re)
    PSIP.add_technology!(p_5bus, t_th_exp)
    PSIP.add_technology!(p_5bus, t_demand)

    PSIP.add_time_series!(p_5bus, t_th, ts_th_cheap_inv_capex)
    PSIP.add_time_series!(p_5bus, t_th_exp, ts_th_exp_inv_capex)

    IS.add_time_series!(p_5bus.data, t_re, ts_wind_2030; year="2030")
    IS.add_time_series!(p_5bus.data, t_re, ts_wind_2035; year="2035")
    PSIP.add_time_series!(p_5bus, t_re, ts_wind_inv_capex)

    IS.add_time_series!(p_5bus.data, t_demand, ts_demand_2030; year="2030")
    IS.add_time_series!(p_5bus.data, t_demand, ts_demand_2035; year="2035")
    t = IS.get_time_series(
        IS.SingleTimeSeries,
        t_re,
        "ops_variable_cap_factor";
        year="2035",
    )
    load = IS.get_time_series(IS.SingleTimeSeries, t_demand, "ops_peak_load"; year="2030")
    #InfrastructureSystems.serialize(p_5bus)

    return p_5bus
end
