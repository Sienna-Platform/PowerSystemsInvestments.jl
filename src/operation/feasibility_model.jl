abstract type FeasibilityModel end

struct EnergyLowerBound <: FeasibilityModel end

struct RepresentativePeriods <: FeasibilityModel
    sample_periods::Vector{Dates.DateTime}
end
