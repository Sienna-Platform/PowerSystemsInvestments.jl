module PowerSystemsInvestments

### Exports ###

### Base models ###
export InvestmentModel
export InvestmentModelTemplate
export TransportModel
export OptimizationProblemOutputs

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
export WeightedEnergyShareDemand

### Functions ###
# Template exports
export set_technology_model!
export set_requirement_model!
# Model Exports
export build!
export solve!
export serialize_problem
export serialize_outputs
#Results interfaces
export read_variable
export read_optimizer_stats
export read_expression
export get_variable
export get_constraint
export get_expression

#### Imports ###

import InfrastructureSystems
import InfrastructureOptimizationModels
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
const IOM = InfrastructureOptimizationModels
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

# Concrete container/store types moved to InfrastructureOptimizationModels in the IS4 split
import InfrastructureOptimizationModels:
    ArgumentConstructStage, 
    ModelConstructStage, 
    OptimizationContainer,
    OptimizationContainerMetadata,
    STORE_CONTAINERS,
    STORE_CONTAINER_DUALS,
    STORE_CONTAINER_EXPRESSIONS,
    STORE_CONTAINER_PARAMETERS,
    STORE_CONTAINER_VARIABLES,
    STORE_CONTAINER_AUX_VARIABLES
import InfrastructureOptimizationModels:
    OptimizationContainerKey,
    VariableKey,
    ConstraintKey,
    ExpressionKey,
    AuxVarKey,
    ParameterKey,
    # Abstract types for dispatch
    VariableType,
    ConstraintType,
    AuxVariableType,
    ParameterType,
    InitialConditionType,
    ExpressionType
import InfrastructureOptimizationModels:
    should_export_variable,
    should_export_dual,
    should_export_parameter,
    should_export_aux_variable,
    should_export_expression,
    # Model internals
    get_output_dir

# Renamed IOM symbols
const OptimizationProblemResults = IOM.OptimizationProblemOutputs
const export_results = IOM.export_outputs
const serialize_results = IOM.serialize_outputs

#TODO: Confirm all of these are accounted for in IOM and then remove commented out imports below
#     should_export_expression
# import InfrastructureSystems.Optimization:
#     get_entry_type, get_component_type, get_output_dir
# import InfrastructureSystems.Optimization:
#     read_results_with_keys,
#     deserialize_key,
#     encode_key_as_string,
#     encode_keys_as_strings,
#     should_write_resulting_value,
#     convert_result_to_natural_units,
#     to_matrix,
#     get_store_container_type
# import InfrastructureSystems.Optimization:
#     OptimizationProblemResults, OptimizationProblemResultsExport, OptimizerStats
# import InfrastructureSystems.Optimization:
#     list_variable_names, list_aux_variable_names, list_dual_names, list_expression_names
# import InfrastructureSystems.Optimization:
#     read_optimizer_stats,
#     get_optimizer_stats,
#     export_results,
#     serialize_results,
#     get_timestamps,
#     get_model_base_power,
#     get_objective_value,
#     read_variable,
#     read_dual,
#     read_expression

import InfrastructureOptimizationModels: get_entry_type, get_component_type, get_output_dir
import InfrastructureSystems.Optimization: should_write_resulting_value
import InfrastructureOptimizationModels:
    deserialize_key, encode_key_as_string, encode_keys_as_strings, get_store_container_type
import InfrastructureOptimizationModels:
    OptimizationProblemOutputs, OptimizationProblemOutputsExport, OptimizerStats
import InfrastructureOptimizationModels:
    list_variable_names, list_aux_variable_names, list_dual_names, list_expression_names
import InfrastructureOptimizationModels:
    AbstractProblemTemplate,
    SparseVariableType,
    read_optimizer_stats,
    get_optimizer_stats,
    get_jump_model,
    get_settings,
    get_variables,
    get_aux_variables,
    get_constraints,
    get_expressions,
    get_duals,
    get_metadata,
    get_initial_time,
    get_resolution,
    get_time_steps,
    get_objective_expression,
    is_milp,
    supports_milp,
    update_objective_function!,
    export_outputs,
    serialize_outputs,
    get_timestamps,
    get_model_base_power,
    get_objective_value,
    read_variable,
    read_dual,
    read_expression,
    get_infeasibility_conflict,
    stores_time_series_in_memory,
    get_default_attributes,
    get_default_time_series_names,
    _set_model!,
    # Re-export commonly used accessors that don't clash
    get_horizon,
    get_optimizer,
    get_direct_mode_optimizer,
    get_optimizer_solve_log_print,
    get_detailed_optimizer_stats,
    get_calculate_conflict,
    get_deserialize_initial_conditions,
    get_store_variable_names,
    get_check_numerical_bounds,
    get_ext,
    set_horizon!,
    set_resolution!,
    set_initial_time!,
    log_values,
    fix_parameter_value,
    to_matrix,
    container_spec,
    sparse_container_spec,
    remove_undef!,
    supports_milp,
    write_optimizer_stats!,
    serialize_jump_optimization_model,
    check_conflict_status,
    get_column_names,
    jump_value,
    tf_html_simple,
    _show_method,
    add_constant_to_jump_expression!,
    add_proportional_to_jump_expression!,
    add_linear_to_jump_expression!
import InfrastructureOptimizationModels:
    TimeMapping, OperationalPeriods, InvestmentIntervals,
    get_consecutive_slices, get_operational_indexes, get_feasibility_indexes,
    get_all_indexes, get_time_stamps, get_investment_time_stamps,
    get_inverse_invest_mapping, get_base_date,
    get_total_period_count, get_total_operation_period_count,
    get_total_feasibility_period_count, get_total_investment_period_count,
    get_time_steps, get_operational_time_steps, get_feasibility_time_steps, get_investment_time_steps,
    is_feasibility_empty, get_investment_map_to_operational_slices, get_operational_weights, get_base_year,
    get_discount_rate, get_inflation_rate, get_status, get_internal, get_run_status, get_store,
    set_output_dir!, set_status!, set_console_level!, set_file_level!, get_recorders, get_recorder_dir,
    get_optimization_container, get_template, get_portfolio, get_time_mapping, get_executions, get_variable,
    ModelStoreParams, set_store_params!, configure_logging, initialize_storage!, get_store_params, is_operation_entry,
    is_investment_entry, set_run_status!, get_allow_fails, AbstractTransportAggregation, TransportModel, get_use_slacks
import InfrastructureOptimizationModels:
    InvestmentVariableType, OperationsVariableType, FeasibilityVariableType,
    BuildInvestmentVariableType, InvestmentExpressionType, OperationsExpressionType, 
    FeasibilityExpressionType, CumulativeInvestmentExpressionType
import InfrastructureOptimizationModels:
    TechnologyModel, RequirementModel,
    AbstractTechnologyFormulation, InvestmentTechnologyFormulation, OperationsTechnologyFormulation, FeasibilityTechnologyFormulation,
    RequirementFormulation, get_technology_type, get_investment_formulation, get_operations_formulation, get_feasibility_formulation,
    get_requirement_type, get_requirement_formulation, get_use_slacks, get_duals
import InfrastructureOptimizationModels: 
    InvestmentModel, InvestmentModelStore,
    Settings, get_portfolio_to_file, get_base_power, get_system_uuid, deserialize_key,
    get_optimizer_stats, set_investment_data!, InvestmentContainerData, OptimizationKeyType,
    LOG_GROUP_OPTIMIZATION_CONTAINER, LOG_GROUP_MODEL_STORE, reset!, built_for_recurrent_solves,
    init_optimization_container!
import TimerOutputs

####
# Order Required #
include("utils/mpi_utils.jl")
include("base/definitions.jl")
# Base #
include("capital/technology_capital_formulations.jl")
include("capital/capital_models.jl")
include("operation/technology_operation_formulations.jl")
include("operation/feasibility_model.jl")
include("operation/operation_model.jl")
include("base/transport_model.jl")
include("base/constraints.jl")
include("base/variables.jl")
include("base/expressions.jl")
include("base/solution_algorithms.jl")
include("requirement_models/requirement_formulations.jl")
include("base/investment_model_template.jl")
include("base/objective_function.jl")
include("base/optimization_container.jl")
# Investment Model #
include("investment_model/investment_model_store.jl")
include("investment_model/investment_model.jl")
include("investment_model/investment_problem_results.jl")
# Serialization #
include("base/serialization.jl")
# Solve Instance #
include("model_build/SingleInstanceSolve.jl")
# Utils #
include("utils/printing_pt_v3.jl")
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
include("requirement_models/requirement_utils.jl")
include("requirement_models/energy_share_requirement.jl")
# Objective Function #
include("technology_models/technologies/common/objective_function/common_financial.jl")
include("technology_models/technologies/common/objective_function/common_capital.jl")
include("technology_models/technologies/common/objective_function/common_operations.jl")
include("technology_models/technologies/common/objective_function/linear_curve.jl")
end
