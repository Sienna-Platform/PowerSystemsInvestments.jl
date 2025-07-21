function validate_available_technologies(
    model::TechnologyModel{D, A, B, C},
    port::PSIP.Portfolio,
) where {
    D <: PSIP.Technology,
    A <: InvestmentTechnologyFormulation,
    B <: OperationsTechnologyFormulation,
    C <: FeasibilityTechnologyFormulation,
}
    technologies = get_available_technologies(model, port)
    if isempty(technologies)
        return false
    end
    # TODO: Implement check of technologies
    #PSY.check_components(system, devices)
    return true
end
