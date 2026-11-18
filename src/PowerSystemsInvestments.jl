module PowerSystemsInvestments

#### Exports ####

### Models ###
export DecisionModel # from InfrastructureOptimizationModels
export InvestmentModelTemplate
export SingleInstanceSolve
export TechnologyModel
export RequirementModel
export TransportModel

### Capital Models ###
export DiscountedCashFlow

### Operation Models ###
export AggregateOperatingCost
export ClusteredRepresentativeDays
export OperationalRepresentativeDays

### Feasibility Models ###
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

### Constraints ###
export NodalBalanceConstraint
export EnergyShareRequirementConstraint
export HydroEnergyBudgetConstraint

### Variables ###
export BuildCapacity
export BuildEnergyCapacity
export BuildPowerCapacity
export BuildSupplyCapacity
export BuildInverterCapacity
export ActivePowerVariable
export ActiveInPowerVariable
export ActiveOutPowerVariable
export ActivePowerChargeVariable
export ActivePowerDischargeVariable
export ActivePowerSupplyVariable
export StateOfChargeVariable
export FlowActivePowerVariable

### Expressions ###
export CumulativeCapacity
export CumulativePowerCapacity
export CumulativeEnergyCapacity
export CumulativeSupplyCapacity
export CumulativeInverterCapacity
export CapitalCost
export TotalCapitalCost
export FixedOperationModelCost
export VariableOMCost
export EnergyBalance
export WeightedEnergyGeneration
export WeightedEnergyDemand
export WeightedEnergyShareGeneration
export WeightedEnergyShareDemand

### Functions ###
# Template
export set_technology_model!
export set_requirement_model!
# Model
export build!
export solve!
export serialize_problem
export optimizer_with_attributes # from JuMP
# Results
export OptimizationProblemOutputs
export serialize_outputs
export read_variable
export read_expression
export read_optimizer_stats
export get_variable
export get_constraint
export get_expression

#### Imports ####

import DataFrames
import DataStructures
import Dates
import InfrastructureOptimizationModels
import InfrastructureSystems
import JuMP
import Logging
import MathOptInterface
import PowerSystems
import PowerSystemsInvestmentsPortfolios
import PrettyTables
import Serialization
import TimeSeries
import TimerOutputs

const IS = InfrastructureSystems
const ISOPT = InfrastructureSystems.Optimization
const IOM = InfrastructureOptimizationModels
const PSY = PowerSystems
const MOI = MathOptInterface
const PSIP = PowerSystemsInvestmentsPortfolios

using DocStringExtensions

@template (FUNCTIONS, METHODS) = """
                                 $(TYPEDSIGNATURES)
                                 $(DOCSTRING)
                                 """

import DataStructures: OrderedDict
import JuMP: optimizer_with_attributes
import JuMP.Containers: DenseAxisArray, SparseAxisArray

# ---- Optimization container, keys, and key types ----
import InfrastructureOptimizationModels:
    OptimizationContainer,
    ArgumentConstructStage,
    ModelConstructStage,
    OptimizationContainerKey,
    VariableKey,
    ConstraintKey,
    ExpressionKey,
    AuxVarKey,
    ParameterKey,
    VariableType,
    ConstraintType,
    AuxVariableType,
    ExpressionType,
    SparseVariableType,
    STORE_CONTAINERS,
    get_entry_type,
    get_metadata,
    encode_key_as_string,
    should_write_resulting_value

# ---- Model, template, store, build/solve lifecycle ----
import InfrastructureOptimizationModels:
    AbstractProblemTemplate,
    DecisionModel,
    ModelStoreParams,
    Settings,
    get_internal,
    get_optimization_container,
    get_template,
    get_system,
    get_store,
    get_store_params,
    set_store_params!,
    init_model_store_params!,
    initialize_storage!,
    built_for_recurrent_solves,
    reset!,
    get_status,
    set_status!,
    get_run_status,
    set_run_status!,
    get_executions,
    get_allow_fails,
    configure_logging,
    register_recorders!,
    unregister_recorders!,
    serialize_optimization_model,
    get_output_dir,
    set_output_dir!,
    set_console_level!,
    set_file_level!

# ---- Settings accessors ----
import InfrastructureOptimizationModels:
    get_initial_time,
    get_resolution,
    get_optimizer,
    get_optimizer_solve_log_print,
    get_portfolio_to_file

# ---- Optimization container accessors ----
import InfrastructureOptimizationModels:
    get_jump_model,
    get_settings,
    get_variable,
    get_variables,
    get_aux_variables,
    get_constraints,
    get_duals,
    get_problem_base_power,
    is_milp,
    update_objective_function!

# ---- Time mapping ----
import InfrastructureOptimizationModels:
    get_time_mapping,
    set_time_mapping!,
    get_time_steps,
    get_base_date,
    get_total_operation_period_count

# ---- Formulations ----
import InfrastructureOptimizationModels:
    AbstractDeviceFormulation,
    AbstractServiceFormulation,
    get_use_slacks,
    get_default_attributes,
    get_default_time_series_names

# ---- Container construction / JuMP helpers ----
import InfrastructureOptimizationModels:
    container_spec,
    sparse_container_spec,
    remove_undef!,
    add_proportional_to_jump_expression!

# ---- Results, outputs, serialization ----
import InfrastructureOptimizationModels:
    OptimizationProblemOutputs,
    get_optimizer_stats,
    read_optimizer_stats,
    write_optimizer_stats!,
    list_variable_keys,
    list_aux_variable_keys,
    list_dual_keys,
    list_expression_keys,
    read_variable,
    read_dual,
    read_expression,
    read_aux_variable,
    get_timestamps,
    export_outputs,
    serialize_outputs,
    check_conflict_status

# ---- Logging & printing ----
import InfrastructureOptimizationModels:
    LOG_GROUP_OPTIMIZATION_CONTAINER, tf_html_simple, _show_method

####
# Order Required #
include("utils/mpi_utils.jl")
include("base/definitions.jl")
include("base/abstract_formulation_types.jl")
# Base #
include("capital/technology_capital_formulations.jl")
include("capital/capital_models.jl")
include("operation/technology_operation_formulations.jl")
include("operation/feasibility_model.jl")
include("operation/operation_model.jl")
include("base/technology_model.jl")
include("base/requirement_model.jl")
include("base/transport_model.jl")
include("base/constraints.jl")
include("base/variables.jl")
include("base/expressions.jl")
include("base/solution_algorithms.jl")
include("requirement_models/requirement_formulations.jl")
include("base/investment_model_template.jl")
include("base/time_mapping.jl")
include("base/objective_function.jl")
include("base/optimization_container.jl")
# Investment Model #
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
