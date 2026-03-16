"""
Investment-specific data stored in OptimizationContainer's `ext` dictionary.
Contains time mapping, financial parameters, and operational weights.
"""
mutable struct InvestmentContainerData
    time_mapping::TimeMapping
    operational_weights::Union{Nothing, Vector{Float64}}
    base_year::Int
    discount_rate::Float64
    inflation_rate::Float64
    interest_rate::Float64
end

function InvestmentContainerData()
    return InvestmentContainerData(
        TimeMapping(nothing),
        nothing,
        2020,
        0.0,
        0.0,
        0.0,
    )
end

const _INVESTMENT_DATA_KEY = "investment_data"

function get_investment_data(
    container::OptimizationContainer,
)::InvestmentContainerData
    return container.settings.ext[_INVESTMENT_DATA_KEY]
end

function set_investment_data!(
    container::OptimizationContainer,
    data::InvestmentContainerData,
)
    container.settings.ext[_INVESTMENT_DATA_KEY] = data
    return
end

get_time_mapping(container::OptimizationContainer) =
    get_investment_data(container).time_mapping
get_operational_weights(container::OptimizationContainer) =
    get_investment_data(container).operational_weights
get_base_year(container::OptimizationContainer) =
    get_investment_data(container).base_year
get_discount_rate(container::OptimizationContainer) =
    get_investment_data(container).discount_rate
get_inflation_rate(container::OptimizationContainer) =
    get_investment_data(container).inflation_rate
get_interest_rate(container::OptimizationContainer) =
    get_investment_data(container).interest_rate

function set_time_mapping!(
    container::OptimizationContainer,
    time_mapping::TimeMapping,
)
    get_investment_data(container).time_mapping = time_mapping
    return
end

function set_operational_weights!(
    container::OptimizationContainer,
    operational_weights::Union{Nothing, Vector{Float64}},
)
    get_investment_data(container).operational_weights = operational_weights
    return
end

function set_base_year!(container::OptimizationContainer, base_year::Int)
    get_investment_data(container).base_year = base_year
    return
end

function set_discount_rate!(container::OptimizationContainer, discount_rate::Float64)
    get_investment_data(container).discount_rate = discount_rate
    return
end

function set_inflation_rate!(container::OptimizationContainer, inflation_rate::Float64)
    get_investment_data(container).inflation_rate = inflation_rate
    return
end

function set_interest_rate!(container::OptimizationContainer, interest_rate::Float64)
    get_investment_data(container).interest_rate = interest_rate
    return
end
