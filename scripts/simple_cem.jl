using HiGHS
using JuMP

abstract type GenTech end
abstract type InvestmentModel end
abstract type OperationModel end
abstract type RegionalModel end
abstract type OptimizationModel end

# Include simplified portfolio
include("portfolio_test.jl")

#struct to define basic capacity expansion model, broken down into operation and InvestmentModel
struct SimpleInvest <: InvestmentModel end
struct SimpleOp <: OperationModel end

#Defining Model types
inv = SimpleInvest()
op = SimpleOp()

# Defining empty dictionaries for constraints, expressions, variables, etc. How is this done in Sienna?

# investment definitions
build = Dict()
capacity = Dict()
build_nonneg = Dict()
cap_bounds = Dict()
capital_costs = Dict()
fom_costs = Dict()

# operations definitions
dispatch = Dict()
dispatch_lb = Dict()
dispatch_ub = Dict()
dispatch_limit = Dict()
demand_matching = Dict()
vom_costs = Dict()

##################
# Investment variables
##################

function add_variables!(model, T::SupplyTechnology{ThermalStandard}, U::SimpleInvest)
    print("Thermal investment variables called \n")
    for t in T.ext["investment_periods"]
        i = findfirst(==(t), T.ext["investment_periods"])

        # Build and capacity variables
        build[T.name, t] = JuMP.@variable(model)
        capacity[T.name, t] = JuMP.@expression(
            model,
            (
                T.ext["initial_capacity"] + sum(
                    build[T.name, t_p] for t_p in T.ext["investment_periods"] if t_p <= t
                )
            )
        )

        # Investment and FOM cost calculations
        capital_costs[T.name, t] =
            JuMP.@expression(model, T.ext["capital_cost"][i] * build[T.name, t])
        fom_costs[T.name, t] =
            JuMP.@expression(model, T.ext["operations_cost"][i] * capacity[T.name, t])
    end
end

function add_variables!(model, T::SupplyTechnology{RenewableDispatch}, U::SimpleInvest)
    print("Renewable investment variables called \n")
    for t in T.ext["investment_periods"]
        i = findfirst(==(t), T.ext["investment_periods"])

        # Build and capacity variables
        build[T.name, t] = JuMP.@variable(model)
        capacity[T.name, t] = JuMP.@expression(
            model,
            (
                T.ext["initial_capacity"] + sum(
                    build[T.name, t_p] for t_p in T.ext["investment_periods"] if t_p <= t
                )
            )
        )

        # Investment and FOM cost calculations
        capital_costs[T.name, t] =
            JuMP.@expression(model, T.ext["capital_cost"][i] * build[T.name, t])
        fom_costs[T.name, t] =
            JuMP.@expression(model, T.ext["operations_cost"][i] * capacity[T.name, t])
    end
end

############
# Operations variables
############

function add_variables!(model, T::SupplyTechnology{ThermalStandard}, U::SimpleOp)
    print("Thermal operation variable called \n")
    for t in T.ext["operational_periods_2"]
        i = findfirst(==(t), T.ext["operational_periods_2"])

        i_mapper = findfirst(
            ==(t_th.ext["investment_operational_periods_map"][t]),
            t_th.ext["investment_periods"],
        )

        #Dispatch Variable
        dispatch[T.name, t] = JuMP.@variable(model)

        #VOM costs
        vom_costs[T.name, t] =
            JuMP.@expression(model, dispatch[T.name, t] * T.ext["variable_cost"][i_mapper])
    end
end

function add_variables!(model, T::SupplyTechnology{RenewableDispatch}, U::SimpleOp)
    print("Renewable operation variable called\n")
    for t in T.ext["operational_periods_2"]
        i = findfirst(==(t), T.ext["operational_periods_2"])

        i_mapper = findfirst(
            ==(t_th.ext["investment_operational_periods_map"][t]),
            t_th.ext["investment_periods"],
        )

        #Dispatch Variable
        dispatch[T.name, t] = JuMP.@variable(model)

        #VOM costs
        vom_costs[T.name, t] =
            JuMP.@expression(model, dispatch[T.name, t] * T.ext["variable_cost"][i_mapper])
    end
end

############
# Investment constraints
############

function add_constraints!(model, T::SupplyTechnology{ThermalStandard}, U::SimpleInvest)
    print("Thermal investment constraints called\n")
    for t in T.ext["investment_periods"]
        i = findfirst(==(t), T.ext["investment_periods"])

        # Build and capacity variable bounds
        build_nonneg[T.name, t] = JuMP.@constraint(model, 0 <= build[T.name, t])
        cap_bounds[T.name, t] = JuMP.@constraint(
            model,
            T.ext["minimum_required_capacity"][i] <=
            capacity[T.name, t] <=
            T.ext["maximum_capacity"]
        )
    end
end

function add_constraints!(model, T::SupplyTechnology{RenewableDispatch}, U::SimpleInvest)
    print("Renewable investment constraints called\n")
    for t in T.ext["investment_periods"]
        i = findfirst(==(t), T.ext["investment_periods"])

        # Build and capacity variable bounds
        build_nonneg[T.name, t] = JuMP.@constraint(model, 0 <= build[T.name, t])
        cap_bounds[T.name, t] = JuMP.@constraint(
            model,
            T.ext["minimum_required_capacity"][i] <=
            capacity[T.name, t] <=
            T.ext["maximum_capacity"]
        )
    end
end

###########
# Operations Constraints
###########

function add_constraints!(model, T::SupplyTechnology{ThermalStandard}, U::SimpleOp)
    print("Thermal operations constraints called\n")
    for t in T.ext["operational_periods_2"]
        i = findfirst(==(t), T.ext["operational_periods_2"])

        i_mapper = findfirst(
            ==(t_th.ext["investment_operational_periods_map"][t]),
            t_th.ext["investment_periods"],
        )

        # Dispatch Variable
        dispatch_lb[T.name, t] = JuMP.@constraint(model, 0 <= dispatch[T.name, t])
        dispatch_ub[T.name, t] = JuMP.@constraint(
            model,
            dispatch[T.name, t] <=
            T.capacity_factor *
            capacity[T.name, T.ext["investment_operational_periods_map"][t]]
        )
    end
end

function add_constraints!(model, T::SupplyTechnology{RenewableDispatch}, U::SimpleOp)
    print("Renewable operations constraints called\n")
    for t in T.ext["operational_periods_2"]
        i = findfirst(==(t), T.ext["operational_periods_2"])

        i_mapper = findfirst(
            ==(t_th.ext["investment_operational_periods_map"][t]),
            t_th.ext["investment_periods"],
        )

        # Dispatch Variable
        dispatch_lb[T.name, t] = JuMP.@constraint(model, 0 <= dispatch[T.name, t])
        dispatch_ub[T.name, t] = JuMP.@constraint(
            model,
            dispatch[T.name, t] <=
            T.ext["variable_capacity_factor"][i] *
            T.capacity_factor *
            capacity[T.name, T.ext["investment_operational_periods_map"][t]]
        )
    end
end

function add_constraints!(model, U::SimpleOp)
    print("system operations constraints called\n")
    for t in T_o
        demand_matching[t] =
            JuMP.@constraint(model, loads[t] <= sum(dispatch[g, t] for g in gens))
    end
end

#############
# Objective function
#############

function add_objective_function!(model)
    JuMP.@objective(
        model,
        Min,
        sum(capital_costs[g, t] + fom_costs[g, t] for g in gens for t in T_i) +
        weights[t] * sum(vom_costs[g, t] for g in gens for t in T_o)
    )
end

##################
# Running the optimization model
##################

#defining toy data for writing model
loads = Dict(1 => 100, 2 => 150, 3 => 175, 4 => 80, 5 => 300, 6 => 120)
weights = Dict(1 => 12, 2 => 12, 3 => 12, 4 => 12, 5 => 12, 6 => 12)

# initialize model
model = JuMP.Model(HiGHS.Optimizer)

# Calling investment variables
add_variables!(model, t_th, inv)
add_variables!(model, t_th_exp, inv)
add_variables!(model, t_re, inv)

# Calling investment constraints
add_constraints!(model, t_th, inv)
add_constraints!(model, t_th_exp, inv)
add_constraints!(model, t_re, inv)

# Calling operation variable definitions
add_variables!(model, t_th, op)
add_variables!(model, t_th_exp, op)
add_variables!(model, t_re, op)

# Calling operation constraint definitions
add_constraints!(model, t_th, op)
add_constraints!(model, t_th_exp, op)
add_constraints!(model, t_re, op)

# Calling demand matching constraints
add_constraints!(model, op)

# Calling objective function
add_objective_function!(model)
