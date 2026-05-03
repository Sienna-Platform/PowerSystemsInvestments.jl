# Compatibility stubs for missing InfrastructureSystems.Optimization types/functions
# These are needed because PowerSystemsInvestments v0.1.0 was written for a different API version

using DataFrames, Dates

# These types don't exist in IS.Optimization v3.5.1 but are used by PSI
# Define them as stubs so the code can run

# Container key types - used extensively in the container structure
abstract type OptimizationContainerKey end
struct VariableKey{T, U} <: OptimizationContainerKey end
VariableKey(t::Type, u::Type, meta::String="") = VariableKey{t, u}()
struct ConstraintKey{T, U} <: OptimizationContainerKey end
ConstraintKey(t::Type, u::Type, meta::String="") = ConstraintKey{t, u}()
struct ExpressionKey{T, U} <: OptimizationContainerKey end
ExpressionKey(t::Type, u::Type, meta::String="") = ExpressionKey{t, u}()
struct AuxVarKey{T, U} <: OptimizationContainerKey end
AuxVarKey(t::Type, u::Type, meta::String="") = AuxVarKey{t, u}()
struct ParameterKey{T, U} <: OptimizationContainerKey end
ParameterKey(t::Type, u::Type, meta::String="") = ParameterKey{t, u}()

# Type classes - used for dispatch
abstract type VariableType end
abstract type ConstraintType end
abstract type AuxVariableType end
abstract type ParameterType end
abstract type InitialConditionType end
abstract type ExpressionType end

# Parameter types
abstract type RightHandSideParameter end
abstract type ObjectiveFunctionParameter end
abstract type TimeSeriesParameter end

# Result containers
mutable struct OptimizationProblemResults
    model::Any  # InvestmentModel or similar
    function OptimizationProblemResults(model::Any=nothing)
        new(model)
    end
end

struct OptimizationProblemResultsExport end
mutable struct OptimizerStats
    detailed_stats::Bool
    timed_solve_time::Union{Float64, Nothing}
    timed_pre_solve_time::Union{Float64, Nothing}
    timed_post_solve_time::Union{Float64, Nothing}
    timed_problem_generation_time::Union{Float64, Nothing}
    solve_bytes_alloc::Union{Int, Nothing}
    sec_in_gc::Union{Float64, Nothing}
    timed_calculate_aux_variables::Union{Float64, Nothing}
    timed_calculate_dual_variables::Union{Float64, Nothing}
    objective_value::Union{Float64, Nothing}
    termination_status::Union{Int, Nothing}
    primal_status::Union{Int, Nothing}
    dual_status::Union{Int, Nothing}
    result_count::Union{Int, Nothing}
    solve_time::Union{Float64, Nothing}
    function OptimizerStats()
        new(false, nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing,
            nothing, nothing, nothing, nothing, nothing, nothing)
    end
end
struct OptimizationContainerMetadata end

# Model store types
abstract type AbstractModelStore end
abstract type AbstractModelStoreParams end

# ModelInternal wraps the optimization container
mutable struct ModelInternal
    container::Any  # SingleOptimizationContainer or similar
    ext::Dict{String, Any}  # Extension dictionary for storing additional data
    function ModelInternal(container::Any=nothing)
        new(container, Dict{String, Any}())
    end
end

# Container key metadata constant
const CONTAINER_KEY_EMPTY_META = ""

# Store container constants
const STORE_CONTAINER_DUALS = :duals
const STORE_CONTAINER_PARAMETERS = :parameters
const STORE_CONTAINER_VARIABLES = :variables
const STORE_CONTAINER_AUX_VARIABLES = :aux_variables
const STORE_CONTAINER_EXPRESSIONS = :expressions
const STORE_CONTAINERS = (
    STORE_CONTAINER_DUALS,
    STORE_CONTAINER_PARAMETERS,
    STORE_CONTAINER_VARIABLES,
    STORE_CONTAINER_AUX_VARIABLES,
    STORE_CONTAINER_EXPRESSIONS,
)

# Status types - use nested modules for namespace but expose constants properly
module ModelBuildStatusModule
    const EMPTY = 1
    const IN_PROGRESS = 2
    const BUILT = 3
    const FAILED = 4
end

module RunStatusModule
    const NOT_READY = 0
    const INITIALIZED = 3
    const SUCCESSFULLY_FINALIZED = 1
    const FAILED = 2
end

const ModelBuildStatus = ModelBuildStatusModule
const RunStatus = RunStatusModule

# Stub functions for compatibility
function set_output_dir!(model_or_internal::Any, path::String)
    # Handle both model objects and internal objects
    try
        if hasfield(typeof(model_or_internal), :internal)
            # It's a model object, extract internal
            internal = model_or_internal.internal
            if hasfield(typeof(internal), :container)
                container = internal.container
                if hasfield(typeof(container), :output_dir)
                    container.output_dir = path
                end
            end
        elseif hasfield(typeof(model_or_internal), :container)
            # It's already an internal object with a container
            if hasfield(typeof(model_or_internal.container), :output_dir)
                model_or_internal.container.output_dir = path
            end
        end
    catch
        # If field access fails, silently continue
    end
    return
end

function get_status(internal::Any)
    if hasfield(typeof(internal), :status)
        return internal.status
    end
    return ModelBuildStatus.BUILT
end

function set_status!(internal::Any, status::Int)
    if hasfield(typeof(internal), :status)
        internal.status = status
    end
    return
end

function set_console_level!(model::Any, level::Any)
    return
end

function set_file_level!(model::Any, level::Any)
    return
end

function get_output_dir(model::Any)
    if hasfield(typeof(model), :container)
        if hasfield(typeof(model.container), :output_dir)
            return model.container.output_dir
        end
    end
    return ""
end

function get_optimization_container(model::Any)
    # Handle InvestmentModel or similar with :internal field
    if hasfield(typeof(model), :internal)
        internal = model.internal
        if !isnothing(internal) && hasfield(typeof(internal), :container)
            return internal.container
        end
    end
    # Handle ModelInternal directly
    if hasfield(typeof(model), :container)
        return model.container
    end
    return nothing
end

function reset!(model::Any)
    # Reset model state - stub implementation
    if hasfield(typeof(model), :internal)
        internal = model.internal
        if hasfield(typeof(internal), :status)
            internal.status = ModelBuildStatus.EMPTY
        end
    end
    return
end

function get_store_params(internal::Any)
    if hasfield(typeof(internal), :store_params)
        return internal.store_params
    end
    return nothing
end

function get_portfolio(model::Any)
    if hasfield(typeof(model), :portfolio)
        return model.portfolio
    end
    return nothing
end

function get_template(model::Any)
    if hasfield(typeof(model), :template)
        return model.template
    end
    return nothing
end

function get_name(model::Any)
    if hasfield(typeof(model), :name)
        return model.name
    end
    return :model
end

function get_store(model::Any)
    if hasfield(typeof(model), :store)
        return model.store
    end
    return nothing
end

function get_run_status(model::Any)
    if hasfield(typeof(model), :internal)
        if hasfield(typeof(model.internal), :run_status)
            return model.internal.run_status
        end
    end
    return RunStatus.NOT_READY
end

function set_run_status!(model::Any, status::Any)
    if hasfield(typeof(model), :internal)
        if hasfield(typeof(model.internal), :run_status)
            model.internal.run_status = status
        else
            # Try to set it anyway
            try
                model.internal.run_status = status
            catch
                # If setting fails, silently continue
            end
        end
    end
    return nothing
end

# Add fields to ModelInternal if needed
function ensure_fields!(internal::ModelInternal)
    if !hasfield(typeof(internal), :status)
        internal.status = ModelBuildStatus.EMPTY
    end
    if !hasfield(typeof(internal), :run_status)
        internal.run_status = RunStatus.NOT_READY
    end
    return internal
end

# Additional compat stubs for store and metadata operations
function get_container(internal::Any)
    if hasfield(typeof(internal), :container)
        return internal.container
    end
    return nothing
end

function set_store_params!(internal::Any, params::Any)
    if hasfield(typeof(internal), :ext) && isa(internal.ext, Dict)
        internal.ext["store_params"] = params
    end
    return
end

# Override get_store_params to also check ext dict
function get_store_params(internal::Any)
    if hasfield(typeof(internal), :store_params)
        return internal.store_params
    end
    if hasfield(typeof(internal), :ext) && isa(internal.ext, Dict)
        return get(internal.ext, "store_params", nothing)
    end
    return nothing
end

function encode_key_as_string(key::Any)
    try
        return string(typeof(key).name.name) * "__" *
               string(key.entry_type.name.name) * "__" *
               string(key.component_type.name.name)
    catch
        return string(key)
    end
end

function encode_keys_as_strings(keys)
    return [encode_key_as_string(k) for k in keys]
end

function has_container_key(meta::Any, key::Any)
    return false
end

function add_container_key!(meta::Any, key::Any, value::Any)
    return nothing
end

function _make_metadata_filename(dir::String)
    return joinpath(dir, "optimization_container_metadata.json")
end

function get_store_container_type(key::Any)
    return :variables
end

function get_entry_type(key::Any)
    # Extract the first type parameter from OptimizationContainerKey subtypes
    # VariableKey{T, U}, ConstraintKey{T, U}, etc. → return T (the entry type)
    try
        t = typeof(key)
        # Get supertype to access type parameters
        if t.name !== nothing && !isempty(t.parameters)
            return first(t.parameters)
        end
    catch
    end
    return key
end

function to_dataframe(stats::OptimizerStats)
    return DataFrames.DataFrame()
end

function should_write_resulting_value(key::Any)
    # Default to false - only types explicitly marked should write results
    return false
end

function serialize_results(results::Any, output_dir::String)
    # Stub for results serialization - results already serialized to HDF5 during solve
    return
end

# Helper function to get interest rate (WACC) from TechnologyFinancialData
function get_wacc_from_tech_financials(financials)
    # Calculate WACC: D * Rd * (1 - Tc) + E * Re
    dr = financials.debt_rate
    tr = financials.tax_rate
    re = financials.return_on_equity
    df = financials.debt_fraction
    ef = 1.0 - df
    return df * dr * (1.0 - tr) + ef * re
end

# Stub for getting current timestamp in solve process
function get_current_timestamp(model::Any)
    # Return nothing as we don't track solve-time state
    return nothing
end

# Stub for checking if failures are allowed
function get_allow_fails(model::Any)
    return false
end

# Exports
export OptimizationContainerKey, VariableKey, ConstraintKey, ExpressionKey, AuxVarKey, ParameterKey
export VariableType, ConstraintType, AuxVariableType, ParameterType, InitialConditionType, ExpressionType
export RightHandSideParameter, ObjectiveFunctionParameter, TimeSeriesParameter
export OptimizationProblemResults, OptimizationProblemResultsExport, OptimizerStats, OptimizationContainerMetadata
export AbstractModelStore, AbstractModelStoreParams, ModelInternal
export CONTAINER_KEY_EMPTY_META
export STORE_CONTAINER_DUALS, STORE_CONTAINER_PARAMETERS, STORE_CONTAINER_VARIABLES
export STORE_CONTAINER_AUX_VARIABLES, STORE_CONTAINER_EXPRESSIONS, STORE_CONTAINERS
export ModelBuildStatus, RunStatus
export set_output_dir!, get_status, set_status!, set_console_level!, set_file_level!
export get_output_dir, get_optimization_container, reset!, get_store_params
export get_container, set_store_params!, encode_key_as_string, encode_keys_as_strings
export has_container_key, add_container_key!, _make_metadata_filename
export get_store_container_type, get_entry_type, to_dataframe, should_write_resulting_value
export serialize_results, get_wacc_from_tech_financials, get_current_timestamp, get_allow_fails
