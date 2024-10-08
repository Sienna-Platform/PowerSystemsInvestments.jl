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
import TimeSeries
import Logging

const IS = InfrastructureSystems
const ISOPT = InfrastructureSystems.Optimization
const PSY = PowerSystems
const MOI = MathOptInterface
const PSIP = PowerSystemsInvestmentsPortfolios
const PM = PowerModels
const PNM = PowerNetworkMatrices

### Exports ###
export InvestmentModel
export InvestmentModelTemplate
export TransportModel

### Capital Model
export DiscountedCashFlow
export AggregateOperatingCost
export RepresentativePeriods

export SingleRegionBalanceModel

## Variables ##
export BuildCapacity
export ActivePowerVariable

## Expressions ##
export CumulativeCapacity
export CapitalCost
export TotalCapitalCost
export FixedOperationModelCost
export VariableOMCost
export SupplyTotal
export DemandTotal

#remove later, just for testing
export objective_function!
export add_expression!
export add_to_expression!

using DocStringExtensions

# methods
export build!

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

import TimerOutputs

####
# Order Required
include("utils/mpi_utils.jl")
include("base/definitions.jl")

include("base/abstract_formulation_types.jl")
include("capital/technology_capital_formulations.jl")
include("capital/capital_models.jl")
include("operation/technology_operation_formulations.jl")
include("operation/feasibility_model.jl")
include("operation/operation_model.jl")
include("base/transport_model.jl")
include("base/constraints.jl")
include("base/variables.jl")
include("base/expressions.jl")
include("base/parameters.jl")
include("base/settings.jl")
include("base/solution_algorithms.jl")
include("base/technology_model.jl")
include("base/investment_model_template.jl")

include("base/objective_function.jl")
include("base/single_optimization_container.jl")
include("base/multi_optimization_container.jl")

include("investment_model/investment_model_store.jl")
include("investment_model/investment_model.jl")

include("model_build/SingleInstanceSolve.jl")

include("utils/printing.jl")
include("utils/jump_utils.jl")
include("technology_models/technologies/common/add_variable.jl")
include("technology_models/technologies/common/add_to_expression.jl")
include("technology_models/technologies/supply_tech.jl")
include("technology_models/technologies/demand_tech.jl")
include("technology_models/technologies/storage_tech.jl")
include("network_models/singleregion_model.jl")

include("technology_models/technology_constructors/supply_constructor.jl")
include("technology_models/technology_constructors/demand_constructor.jl")
include("technology_models/technology_constructors/storage_constructor.jl")

include("technology_models/technologies/common/objective_function.jl/common_capital.jl")
include("technology_models/technologies/common/objective_function.jl/common_operations.jl")
include("technology_models/technologies/common/objective_function.jl/linear_curve.jl")
end
