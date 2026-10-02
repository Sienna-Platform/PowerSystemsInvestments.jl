const UNSET_HORIZON = Dates.Millisecond(0)
const UNSET_RESOLUTION = Dates.Millisecond(0)
const UNSET_INI_TIME = Dates.DateTime(0)

const SECONDS_IN_MINUTE = 60.0
const MINUTES_IN_HOUR = 60.0
const SECONDS_IN_HOUR = 3600.0
const MILLISECONDS_IN_HOUR = 3600000.0
const MAX_START_STAGES = 3
const OBJECTIVE_FUNCTION_POSITIVE = 1.0
const OBJECTIVE_FUNCTION_NEGATIVE = -1.0
const SINGLE_REGION = "SingleRegion"

# Timers
const BUILD_PROBLEMS_TIMER = TimerOutputs.TimerOutput()
const RUN_OPERATION_MODEL_TIMER = TimerOutputs.TimerOutput()

# Type Alias for JuMP containers
const GAE = JuMP.GenericAffExpr{Float64, JuMP.VariableRef}
const JuMPAffineExpressionArray = Matrix{GAE}
const JuMPAffineExpressionVector = Vector{GAE}

# File definitions
const PROBLEM_LOG_FILENAME = "investment_problem.log"

# Enums
const ModelBuildStatus = ISOPT.ModelBuildStatus
const RunStatus = IS.Simulation.RunStatus

# PSI-specific: more retries than IOM default
const MAX_OPTIMIZE_TRIES = 10

# Import shared name delimiter
const PSI_NAME_DELIMITER = "__"
