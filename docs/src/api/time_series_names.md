# [Time Series Names](@id time_series_names)

`PowerSystemsInvestments.jl` reads time series from the technologies in a `Portfolio` by
name. This page lists the names each formulation looks for and how each series must be
tagged.

## Names

| Technology type                                                          | Formulation                                                                   | Time series name                  | Content                                                                |
|:------------------------------------------------------------------------ |:----------------------------------------------------------------------------- |:--------------------------------- |:---------------------------------------------------------------------- |
| `DemandRequirement`                                                      | [`BasicDispatch`](@ref)                                                       | `"ops_demand"`                    | Demand in each time step, in MW                                        |
| `SupplyTechnology{RenewableDispatch}`, `SupplyTechnology{HydroDispatch}` | [`BasicDispatch`](@ref)                                                       | `"ops_variable_cap_factor"`       | Capacity factor in each time step, as a fraction of installed capacity |
| `SupplyTechnology{HydroDispatch}`                                        | [`BasicDispatchWithBudget`](@ref)                                             | `"ops_hydro_budget"`              | Energy budget in each time step, as a fraction of installed capacity   |
| `ColocatedSupplyStorageTechnology`                                       | [`ChronologicalColocatedDispatch`](@ref), [`CyclicalColocatedDispatch`](@ref) | `"ops_wind_variable_cap_factor"`  | Wind capacity factor in each time step                                 |
| `ColocatedSupplyStorageTechnology`                                       | [`ChronologicalColocatedDispatch`](@ref), [`CyclicalColocatedDispatch`](@ref) | `"ops_solar_variable_cap_factor"` | Solar capacity factor in each time step                                |

`SupplyTechnology{ThermalStandard}`, `StorageTechnology`, and transport technologies do not
need time series.

The names are fixed. They cannot be changed through the template.

## Type and features

Each time series must be a `SingleTimeSeries`. A technology needs one series for each
operational period, and each series is identified by two features:

| Feature     | Type     | Value                                                                                                        |
|:----------- |:-------- |:------------------------------------------------------------------------------------------------------------ |
| `"year"`    | `String` | Year of the first time stamp of the operational period, e.g. `"2030"`                                        |
| `"rep_day"` | `Int`    | Position of the operational period in the `representative_series` of the operation cost model, starting at 1 |

`"rep_day"` counts across all operational periods of the model, not within a year. If the
operation cost model has two periods in 2030 and two in 2035, they are numbered 1 to 4.

## Length and time stamps

Each series must have one value for each time step of its operational period, in the same
order. The first time stamp of the series is expected to be the first time stamp of the
operational period; a mismatch is reported as an error in the log but does not stop the
build.
