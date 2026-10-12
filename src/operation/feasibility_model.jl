"""
Abstract supertype for the models used to check the feasibility of an investment plan.
"""
abstract type FeasibilityModel end

struct EnergyLowerBound <: FeasibilityModel end

"""
Feasibility model that checks an investment plan against a set of sampled periods.

# Arguments

  - `sample_periods::Vector{Vector{Dates.DateTime}}`: Time stamps of each feasibility
    period. Pass an empty vector to build a model without feasibility periods.
"""
struct RepresentativePeriods <: FeasibilityModel
    sample_periods::Vector{Vector{Dates.DateTime}}
end
