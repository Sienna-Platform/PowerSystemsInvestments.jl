using Pkg
Pkg.activate("")
Pkg.instantiate()
using Revise
import InfrastructureSystems
using PowerSystemsInvestmentsPortfolios
using PowerSystemsInvestments
using PowerSystems
using JuMP
using HiGHS
const IS = InfrastructureSystems
const PSIP = PowerSystemsInvestmentsPortfolios
const PSY = PowerSystems
const PSIN = PowerSystemsInvestments

include("portfolio_test.jl")

temp_container["model"] = JuMP.Model(HiGHS.Optimizer)

### Utils ###
GAE = JuMP.GenericAffExpr{Float64, JuMP.VariableRef}
function container_spec(::Type{T}, axs...) where {T <: Any}
    return PSIN.DenseAxisArray{T}(undef, axs...)
end
function remove_undef!(expression_array::AbstractArray)
    # iteration is deliberately unsupported for CartesianIndex
    # Makes this code a bit hacky to be able to use isassigned with an array of arbitrary size.
    for i in CartesianIndices(expression_array.data)
        if !isassigned(expression_array.data, i.I...)
            expression_array.data[i] = zero(eltype(expression_array))
        end
    end

    return expression_array
end

##############################
#### Investment variables ####
##############################

function add_variables!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.ContinuousInvestment,
) where {T <: PSIN.BuildCapacity}
    model = container["model"]
    variables = container["variables"]
    tech_names = PSIP.get_name.(techs)
    inv_periods = container["data"]["investment_periods"]

    # This should be replaced by add_variable_container!
    var = container_spec(JuMP.VariableRef, tech_names, inv_periods)
    variables[PSIN.BuildCapacity] = var

    for name in tech_names
        for t in inv_periods
            # Build and capacity variables        
            var[name, t] = JuMP.@variable(
                model,
                base_name = "$(T)_{$(name), $(t)}",
                lower_bound = 0.0,
            )
        end
    end
end

##############################
#### Operations variables ####
##############################

function add_variables!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.BasicDispatch,
) where {T <: PSIN.Dispatch}
    model = container["model"]
    variables = container["variables"]
    tech_names = PSIP.get_name.(techs)
    op_periods = container["data"]["operational_periods"]

    # This should be replaced by add_variable_container!
    var = container_spec(JuMP.VariableRef, tech_names, op_periods)
    variables[PSIN.Dispatch] = var

    for name in tech_names
        for t in op_periods
            var[name, t] = JuMP.@variable(
                model,
                base_name = "$(T)_{$(name), $(t)}",
                lower_bound = 0.0,
            )
        end
    end
end

###################################
##### Investment Expressions ######
###################################

function add_expressions!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.ContinuousInvestment,
) where {T <: PSIN.CumulativeCapacity}
    expressions = container["expressions"]
    tech_names = PSIP.get_name.(techs)
    inv_periods = container["data"]["investment_periods"]

    # This should be replaced by add_expression_container!
    expr = container_spec(GAE, tech_names, inv_periods)
    remove_undef!(expr)
    expressions[T] = expr
    var = container["variables"][PSIN.BuildCapacity]

    for tech in techs
        name = PSIP.get_name(tech)
        initial_cap = PSIP.get_initial_capacity(tech)
        for t in inv_periods
            JuMP.add_to_expression!(expr[name, t], initial_cap)
            for t_p in inv_periods
                if t_p <= t
                    JuMP.add_to_expression!(expr[name, t], 1.0, var[name, t_p])
                end
            end
        end
    end
end

function add_expressions!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.ContinuousInvestment,
) where {T <: PSIN.CapitalCost}
    expressions = container["expressions"]
    tech_names = PSIP.get_name.(techs)
    inv_periods = container["data"]["investment_periods"]

    # This should be replaced by add_expression_container!
    expr = container_spec(GAE, tech_names, inv_periods)
    remove_undef!(expr)
    expressions[T] = expr
    var = container["variables"][PSIN.BuildCapacity]

    for tech in techs
        name = PSIP.get_name(tech)
        capex = container["components"][name].ext["capital_cost"]
        for t in inv_periods
            JuMP.add_to_expression!(expr[name, t], capex[t], var[name, t])
        end
    end
end

function add_expressions!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.ContinuousInvestment,
) where {T <: PSIN.FixedOMCost}
    expressions = container["expressions"]
    tech_names = PSIP.get_name.(techs)
    inv_periods = container["data"]["investment_periods"]

    # This should be replaced by add_expression_container!
    expr = container_spec(GAE, tech_names, inv_periods)
    remove_undef!(expr)
    expressions[T] = expr
    var = container["expressions"][PSIN.CumulativeCapacity]

    for tech in techs
        name = PSIP.get_name(tech)
        fom = container["components"][name].ext["operations_cost"]
        for t in inv_periods
            JuMP.add_to_expression!(expr[name, t], fom[t], var[name, t])
        end
    end
end

##################################
##### Operation Expressions ######
##################################

function add_expressions!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.BasicDispatch,
) where {T <: PSIN.VariableOMCost}
    expressions = container["expressions"]
    tech_names = PSIP.get_name.(techs)
    op_periods = container["data"]["operational_periods"]

    # This should be replaced by add_expression_container!
    expr = container_spec(GAE, tech_names, op_periods)
    remove_undef!(expr)
    expressions[T] = expr
    var = container["variables"][PSIN.Dispatch]

    for tech in techs
        name = PSIP.get_name(tech)
        vom = container["components"][name].ext["variable_cost"]
        for t in op_periods
            p = container["data"]["investment_operational_periods_map"][t]
            JuMP.add_to_expression!(expr[name, t], vom[p], var[name, t])
        end
    end
end

function add_expressions!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.BasicDispatch,
) where {T <: PSIN.SupplyTotal}
    expressions = container["expressions"]
    tech_names = PSIP.get_name.(techs)
    op_periods = container["data"]["operational_periods"]

    # This should be replaced by add_expression_container!
    expr = container_spec(GAE, op_periods)
    remove_undef!(expr)
    expressions[T] = expr
    var = container["variables"][PSIN.Dispatch]

    for tech in techs
        name = PSIP.get_name(tech)
        for t in op_periods
            JuMP.add_to_expression!(expr[t], 1.0, var[name, t])
        end
    end
end

function add_expressions!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.NoDispatch,
) where {T <: PSIN.SupplyTotal}
    expressions = container["expressions"]
    tech_names = PSIP.get_name.(techs)
    op_periods = container["data"]["operational_periods"]

    # This should be replaced by add_expression_container!
    expr = container_spec(GAE, op_periods)
    remove_undef!(expr)
    expressions[T] = expr
    cap = container["expressions"][PSIN.CumulativeCapacity]

    for tech in techs
        name = PSIP.get_name(tech)
        derate = container["components"][name].capacity_factor
        for t in op_periods
            p = container["data"]["investment_operational_periods_map"][t]
            JuMP.add_to_expression!(expr[t], derate, cap[name, p])
        end
    end
end

function add_expressions!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.BasicDispatch,
) where {T <: PSIN.DemandTotal}
    expressions = container["expressions"]
    op_periods = container["data"]["operational_periods"]

    # This should be replaced by add_expression_container!
    expr = container_spec(GAE, op_periods)
    remove_undef!(expr)
    expressions[T] = expr
    peak = container["components"]["demand"].peak_load
    var = container["components"]["demand"].ext["load_scale_factor"]

    for t in op_periods
        JuMP.add_to_expression!(expr[t], peak, var[t])
    end
end

function add_expressions!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.NoDispatch,
) where {T <: PSIN.DemandTotal}
    expressions = container["expressions"]
    op_periods = container["data"]["operational_periods"]

    # This should be replaced by add_expression_container!
    expr = container_spec(GAE, op_periods)
    remove_undef!(expr)
    expressions[T] = expr
    peak = container["components"]["demand"].peak_load
    var = container["components"]["demand"].ext["load_scale_factor"]

    for t in op_periods
        JuMP.add_to_expression!(expr[t], peak, var[t])
    end
end

###################################
##### Investment Constraints ######
###################################

function add_constraints!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.ContinuousInvestment,
) where {T <: PSIN.MaximumCumulativeCapacity}
    model = container["model"]
    constraints = container["constraints"]
    tech_names = PSIP.get_name.(techs)
    inv_periods = container["data"]["investment_periods"]

    # This should be replaced by add_expression_container!
    cons = container_spec(JuMP.ConstraintRef, tech_names, inv_periods)
    constraints[T] = cons
    expr = container["expressions"][PSIN.CumulativeCapacity]

    for tech in techs
        name = PSIP.get_name(tech)
        max_cap = PSIP.get_maximum_capacity(tech)
        for t in inv_periods
            cons[name, t] = JuMP.@constraint(model, expr[name, t] <= max_cap)
        end
    end
end

function add_constraints!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.ContinuousInvestment,
) where {T <: PSIN.MinimumCumulativeCapacity}
    model = container["model"]
    constraints = container["constraints"]
    tech_names = PSIP.get_name.(techs)
    inv_periods = container["data"]["investment_periods"]

    # This should be replaced by add_expression_container!
    cons = container_spec(JuMP.ConstraintRef, tech_names, inv_periods)
    constraints[T] = cons
    expr = container["expressions"][PSIN.CumulativeCapacity]

    for tech in techs
        name = PSIP.get_name(tech)
        min_cap = container["components"][name].ext["minimum_required_capacity"]
        for t in inv_periods
            cons[name, t] = JuMP.@constraint(model, min_cap[t] <= expr[name, t])
        end
    end
end

###################################
##### Operations Constraints ######
###################################

function add_constraints!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.BasicDispatch,
) where {T <: PSIN.MaximumDispatch}
    model = container["model"]
    constraints = container["constraints"]
    tech_names = PSIP.get_name.(techs)
    op_periods = container["data"]["operational_periods"]

    # This should be replaced by add_expression_container!
    cons = container_spec(JuMP.ConstraintRef, tech_names, op_periods)
    constraints[T] = cons
    expr = container["expressions"][PSIN.CumulativeCapacity]
    var = container["variables"][PSIN.Dispatch]

    for tech in techs
        name = PSIP.get_name(tech)
        derate = container["components"][name].capacity_factor
        for t in op_periods
            p = container["data"]["investment_operational_periods_map"][t]
            cons[name, t] = JuMP.@constraint(model, var[name, t] <= derate * expr[name, p])
        end
    end
end

function add_constraints!(
    container,
    ::Type{T},
    techs::Vector{SupplyTechnology},
    formulation::PSIN.OperationsTechnologyFormulation,
) where {T <: PSIN.SupplyDemandBalance}
    model = container["model"]
    constraints = container["constraints"]
    op_periods = container["data"]["operational_periods"]

    # This should be replaced by add_expression_container!
    cons = container_spec(JuMP.ConstraintRef, op_periods)
    constraints[T] = cons
    supply = container["expressions"][PSIN.SupplyTotal]
    demand = container["expressions"][PSIN.DemandTotal]

    for t in op_periods
        cons[t] = JuMP.@constraint(model, supply[t] >= demand[t])
    end
end

### Construction Stage ###
temp_container["model"] = JuMP.Model(HiGHS.Optimizer)
techs = [t_th, t_th_exp, t_re];
formulation = PSIN.ContinuousInvestment()
op_formulation = PSIN.NoDispatch()
#op_formulation = PSIN.BasicDispatch()

### Investment

# Variables
add_variables!(temp_container, PSIN.BuildCapacity, techs, formulation)

# Expressions
add_expressions!(temp_container, PSIN.CumulativeCapacity, techs, formulation)
add_expressions!(temp_container, PSIN.CapitalCost, techs, formulation)
add_expressions!(temp_container, PSIN.FixedOMCost, techs, formulation)

# Constraints
add_constraints!(temp_container, PSIN.MaximumCumulativeCapacity, techs, formulation)
add_constraints!(temp_container, PSIN.MinimumCumulativeCapacity, techs, formulation)

if typeof(op_formulation) == PSIN.NoDispatch
    ### Operations (No Dispatch)

    # Expressions
    add_expressions!(temp_container, PSIN.SupplyTotal, techs, op_formulation)
    add_expressions!(temp_container, PSIN.DemandTotal, techs, op_formulation)

    # Constraints
    add_constraints!(temp_container, PSIN.SupplyDemandBalance, techs, op_formulation)
else
    ### Operations (Basic Dispatch)

    # Variables
    add_variables!(temp_container, PSIN.Dispatch, techs, op_formulation)

    # Expressions
    add_expressions!(temp_container, PSIN.VariableOMCost, techs, op_formulation)
    add_expressions!(temp_container, PSIN.SupplyTotal, techs, op_formulation)
    add_expressions!(temp_container, PSIN.DemandTotal, techs, op_formulation)

    # Constraints
    add_constraints!(temp_container, PSIN.MaximumDispatch, techs, op_formulation)

    add_constraints!(temp_container, PSIN.SupplyDemandBalance, techs, op_formulation)
end
