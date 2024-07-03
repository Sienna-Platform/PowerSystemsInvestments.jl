module PowerSystemsInvestments

import InfrastructureSystems
import PowerSystems
import JuMP
import MathOptInterface
import PowerSystemsInvestmentsPortfolios
import Dates
import PowerModels
import DataStructures
import PowerNetworkMatrices
import PrettyTables

const IS = InfrastructureSystems
const ISOPT = InfrastructureSystems.Optimization
const PSY = PowerSystems
const MOI = MathOptInterface
const PSIP = PowerSystemsInvestmentsPortfolios
const PM = PowerModels
const PNM = PowerNetworkMatrices

### Exports ###

export InvestmentModel
export SimpleCapacityExpansion

## Variables ##
export BuildCapacity

## Expressions ##
export CumulativeCapacity
export CapitalCost
export TotalCapitalCost
export FixedOMCost

using DocStringExtensions

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

#### Imports ###
# DS
import DataStructures: OrderedDict, Deque, SortedDict

# JuMP
import JuMP: optimizer_with_attributes
import JuMP.Containers: DenseAxisArray, SparseAxisArray
export optimizer_with_attributes

# IS.Optimization imports that stay private, may or may not be additional methods in PowerSimulations
import InfrastructureSystems.Optimization: ArgumentConstructStage, ModelConstructStage
import InfrastructureSystems.Optimization:
    STORE_CONTAINERS,
    STORE_CONTAINER_DUALS,
    STORE_CONTAINER_EXPRESSIONS,
    STORE_CONTAINER_PARAMETERS,
    STORE_CONTAINER_VARIABLES,
    STORE_CONTAINER_AUX_VARIABLES
import InfrastructureSystems.Optimization:
    OptimizationContainerKey,
    VariableKey,
    ConstraintKey,
    ExpressionKey,
    AuxVarKey,
    InitialConditionKey,
    ParameterKey
import InfrastructureSystems.Optimization:
    RightHandSideParameter, ObjectiveFunctionParameter, TimeSeriesParameter
import InfrastructureSystems.Optimization:
    VariableType,
    ConstraintType,
    AuxVariableType,
    ParameterType,
    InitialConditionType,
    ExpressionType
import InfrastructureSystems.Optimization:
    should_export_variable,
    should_export_dual,
    should_export_parameter,
    should_export_aux_variable,
    should_export_expression
import InfrastructureSystems.Optimization:
    get_entry_type, get_component_type, get_output_dir
import InfrastructureSystems.Optimization:
    read_results_with_keys,
    deserialize_key,
    encode_key_as_string,
    encode_keys_as_strings,
    should_write_resulting_value,
    convert_result_to_natural_units,
    to_matrix,
    get_store_container_type
####

include("base/formulations.jl")
include("base/investment_model_store.jl")
include("base/network_model.jl")
include("base/constraints.jl")
include("base/variables.jl")
include("base/expressions.jl")
include("base/parameters.jl")
include("base/settings.jl")
include("base/solution_algorithms.jl")
include("base/operation_model.jl")
include("base/feasibility_model.jl")
include("base/investment_problem.jl")
include("investment/investment_model.jl")

# Order Required
include("base/technology_model.jl")
include("investment/problem_template.jl")
include("base/optimization_container.jl")

include("utils/printing.jl")
include("technology_models/technologies/supply_tech.jl")
end
