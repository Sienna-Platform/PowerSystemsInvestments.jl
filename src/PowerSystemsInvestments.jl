module PowerSystemsInvestments

### Exports ###

### Base models ###
export InvestmentModel
export InvestmentModelTemplate
export TransportModel
export OptimizationProblemResults

### Algorithms ###
export SingleInstanceSolve

### Technology Models ###
export TechnologyModel

### Requirement Models ###
export RequirementModel

### Capital Model ###
export DiscountedCashFlow

### Operation Model ###
export AggregateOperatingCost
export ClusteredRepresentativeDays
export OperationalRepresentativeDays

### Feasibility Model ###
export RepresentativePeriods

### Investment Formulations ###
export StaticLoadInvestment
export ContinuousInvestment
export IntegerInvestment
export BinaryInvestment

### Operation Formulations ###
export BasicDispatch
export BasicDispatchWithBudget
export BasicDispatchFeasibility
export ChronologicalStorageDispatch
export CyclicalStorageDispatch
export ChronologicalColocatedDispatch
export CyclicalColocatedDispatch

### Requirement Formulations ###
export RequirementEnergyShare

### Transport Formulations ###
export SingleRegionBalanceModel
export MultiRegionBalanceModel
export NodalBalanceModel
export NodalBalanceConstraint
export EnergyShareRequirementConstraint
export HydroEnergyBudgetConstraint

### Variables ###
export BuildCapacity
export ActivePowerVariable
export BuildEnergyCapacity
export BuildPowerCapacity
export BuildWindCapacity
export BuildSolarCapacity
export BuildInverterCapacity
export ActiveInPowerVariable
export ActiveOutPowerVariable
export StateOfChargeVariable
export ActivePowerChargeVariable
export ActivePowerDischargeVariable
export ActivePowerWindVariable
export ActivePowerSolarVariable
export FlowActivePowerVariable

### Expressions ###
export CumulativeCapacity
export CapitalCost
export TotalCapitalCost
export FixedOperationModelCost
export VariableOMCost
export EnergyBalance
export CumulativePowerCapacity
export CumulativeEnergyCapacity
export CumulativeSolarCapacity
export CumulativeWindCapacity
export CumulativeInverterCapacity
export WeightedEnergyGeneration
export WeightedEnergyDemand
export WeightedEnergyShareGeneration

### Functions ###
# methods
export build!
# Template exports
export set_technology_model!
export set_requirement_model!
# Model Exports
export solve!
export get_initial_conditions
export get_infeasibility_conflict
export serialize_problem
export serialize_results
#Results interfaces
export read_variable
export read_optimizer_stats
export read_expression
export get_variable
export get_constraint
export get_expression

#### Imports ###

import InfrastructureSystems
import PowerSystems
import JuMP
import MathOptInterface
import PowerSystemsInvestmentsPortfolios
import Dates
import PowerModels
import DataStructures
import PrettyTables
import TimeSeries
import Logging
import TimerOutputs
import Serialization
import DataFrames

const IS = InfrastructureSystems
const ISOPT = InfrastructureSystems.Optimization
const PSY = PowerSystems
const MOI = MathOptInterface
const PSIP = PowerSystemsInvestmentsPortfolios
const PM = PowerModels
const MOPFM = MOI.FileFormats.Model

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

# Base imports
import Base.isempty

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
import InfrastructureSystems.Optimization:
    OptimizationProblemResults, OptimizationProblemResultsExport, OptimizerStats
import InfrastructureSystems.Optimization:
    list_variable_names, list_aux_variable_names, list_dual_names, list_expression_names
import InfrastructureSystems.Optimization:
    read_optimizer_stats,
    get_optimizer_stats,
    export_results,
    serialize_results,
    get_timestamps,
    get_model_base_power,
    get_objective_value,
    read_variable,
    read_dual,
    read_expression
import TimerOutputs

####
# Order Required #
include("utils/mpi_utils.jl")
include("utils/jump_utils.jl")
include("base/definitions.jl")
include("base/simulation.jl")
# Base #
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
include("base/settings.jl")
include("base/solution_algorithms.jl")
include("base/technology_model.jl")
include("requirement_models/requirement_formulations.jl")
include("base/requirement_model.jl")
include("base/investment_model_template.jl")
include("base/time_mapping.jl")
include("base/objective_function.jl")
include("base/single_optimization_container.jl")
include("base/multi_optimization_container.jl")
# Investment Model #
include("investment_model/investment_model_store.jl")
include("investment_model/investment_model.jl")
include("investment_model/investment_problem_results.jl")
# Serialization #
include("base/serialization.jl")
# Solve Instance #
include("model_build/SingleInstanceSolve.jl")
# Utils #
@static if pkgversion(PrettyTables).major == 2
    include("utils/printing_pt_v2.jl")
else
    include("utils/printing_pt_v3.jl")
end
include("utils/logging.jl")
include("utils/psip_utils.jl")
# Technology Models #
include("technology_models/technologies/common/add_variable.jl")
include("technology_models/technologies/common/add_to_expression.jl")
include("technology_models/technologies/supply_tech.jl")
include("technology_models/technologies/demand_tech.jl")
include("technology_models/technologies/storage_tech.jl")
include("technology_models/technologies/colocated_tech.jl")
include("technology_models/technologies/branch_tech.jl")
# Network #
include("network_models/singleregion_model.jl")
include("network_models/multiregion_model.jl")
include("network_models/nodal_model.jl")
include("network_models/transport_constructor.jl")
# Constructors #
include("technology_models/technology_constructors/supply_constructor.jl")
include("technology_models/technology_constructors/demand_constructor.jl")
include("technology_models/technology_constructors/storage_constructor.jl")
include("technology_models/technology_constructors/colocated_constructor.jl")
include("technology_models/technology_constructors/branch_constructor.jl")
include("technology_models/technology_constructors/constructor_validations.jl")
# Requirement Models #
include("requirement_models/requirement_constructor.jl")
include("requirement_models/energy_share_requirement.jl")
# Objective Function #
include("technology_models/technologies/common/objective_function/common_financial.jl")
include("technology_models/technologies/common/objective_function/common_capital.jl")
include("technology_models/technologies/common/objective_function/common_operations.jl")
include("technology_models/technologies/common/objective_function/linear_curve.jl")
end
