const GAEVF = JuMP.GenericAffExpr{Float64, VariableRef}
const GQEVF = JuMP.GenericQuadExpr{Float64, VariableRef}

function moi_tests(
    model::InvestmentModel,
    vars::Int,
    interval::Int,
    lessthan::Int,
    greaterthan::Int,
    equalto::Int,
    binary::Bool,
)
    JuMPmodel = PSIN.get_jump_model(model)
    @test JuMP.num_variables(JuMPmodel) == vars
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.Interval{Float64}) == interval
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.LessThan{Float64}) == lessthan
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.GreaterThan{Float64}) == greaterthan
    @test JuMP.num_constraints(JuMPmodel, GAEVF, MOI.EqualTo{Float64}) == equalto
    @test ((JuMP.VariableRef, MOI.ZeroOne) in JuMP.list_of_constraint_types(JuMPmodel)) ==
          binary

    return
end

function psin_constraint_test(
    model::InvestmentModel,
    constraint_keys::Vector{<:PSIN.ConstraintKey},
)
    constraints = PSIN.get_constraints(model)
    for con in constraint_keys
        if get(constraints, con, nothing) !== nothing
            @test true
        else
            @error con
            @test false
        end
    end
    return
end

function psin_checksolve_test(model::InvestmentModel, status, expected_result, tol=0.0)
    res = solve!(model)
    model = PSIN.get_jump_model(model)
    @test termination_status(model) in status
    obj_value = JuMP.objective_value(model)
    @test isapprox(obj_value, expected_result, atol=tol)
end

function check_variable_unbounded(
    model::InvestmentModel,
    ::Type{T},
    ::Type{U},
) where {T <: PSIN.VariableType, U <: PSIP.Technology}
    return check_variable_unbounded(model::InvestmentModel, PSIN.VariableKey(T, U))
end

function check_variable_unbounded(model::InvestmentModel, var_key::PSIN.VariableKey)
    psi_cont = PSIN.get_optimization_container(model)
    variable = PSIN.get_variable(psi_cont, var_key)
    for var in variable
        if JuMP.has_lower_bound(var) || JuMP.has_upper_bound(var)
            return false
        end
    end
    return true
end

function check_variable_bounded(
    model::InvestmentModel,
    ::Type{T},
    ::Type{U},
) where {T <: PSIN.VariableType, U <: PSIP.Technology}
    return check_variable_bounded(model, PSIN.VariableKey(T, U))
end

function check_variable_bounded(model::InvestmentModel, var_key::PSIN.VariableKey)
    psi_cont = PSIN.get_optimization_container(model)
    variable = PSIN.get_variable(psi_cont, var_key)
    for var in variable
        if !JuMP.has_lower_bound(var) || !JuMP.has_upper_bound(var)
            return false
        end
    end
    return true
end

function check_flow_variable_values(
    model::InvestmentModel,
    ::Type{T},
    ::Type{U},
    device_name::String,
    limit::Float64,
) where {T <: PSIN.VariableType, U <: PSIP.Technology}
    psi_cont = PSIN.get_optimization_container(model)
    variable = PSIN.get_variable(psi_cont, T(), U)
    for var in variable[device_name, :]
        if !(PSIN.jump_value(var) <= (limit + 1e-2))
            @error "$device_name out of bounds $(PSIN.jump_value(var))"
            return false
        end
    end
    return true
end
