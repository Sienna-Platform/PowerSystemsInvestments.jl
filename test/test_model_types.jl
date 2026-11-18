@testset "TechnologyModel" begin
    tech = PSIP.SupplyTechnology{PSY.ThermalStandard}
    model = TechnologyModel(
        tech,
        ContinuousInvestment,
        BasicDispatch,
        BasicDispatchFeasibility;
        use_slacks=true,
        attributes=Dict{String, Any}("k" => 42),
    )
    @test PSIN.get_technology_type(model) == tech
    @test PSIN.get_investment_formulation(model) == ContinuousInvestment
    @test PSIN.get_operations_formulation(model) == BasicDispatch
    @test PSIN.get_feasibility_formulation(model) == BasicDispatchFeasibility
    @test model.use_slacks
    @test model.attributes["k"] == 42

    dict = Dict{Any, Vector{String}}()
    PSIN._set_model!(dict, ["a", "b"], model)
    @test dict[model] == ["a", "b"]
    @test_logs (:warn, r"Overwriting") PSIN._set_model!(dict, ["c"], model)
end

@testset "RequirementModel" begin
    req = PSIP.EnergyShareRequirements
    model = RequirementModel(
        req,
        PSIN.RequirementEnergyShare;
        attributes=Dict{String, Any}("x" => 7),
    )
    @test PSIN.get_requirement_type(model) == req
    @test PSIN.get_requirement_formulation(model) == PSIN.RequirementEnergyShare
    @test !PSIN.get_use_slacks(model)
    @test isempty(PSIN.get_duals(model))
    @test PSIN.get_attributes(model)["x"] == 7

    dict = Dict{Any, Vector{String}}()
    PSIN._set_model!(dict, ["r"], model)
    @test dict[model] == ["r"]
    @test_logs (:warn, r"Overwriting.*requirement") PSIN._set_model!(dict, ["s"], model)
end

@testset "TransportModel" begin
    @test !PSIN.get_use_slacks(TransportModel(SingleRegionBalanceModel))
    @test PSIN.get_use_slacks(TransportModel(MultiRegionBalanceModel; use_slacks=true))
end
