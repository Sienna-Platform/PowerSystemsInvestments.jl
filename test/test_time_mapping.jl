@testset "InvestmentTimeMapping" begin
    no_feasibility = Vector{Vector{DateTime}}()

    @testset "Two investment intervals, no feasibility" begin
        invest =
            [(Date(2030, 1, 1), Date(2030, 12, 31)), (Date(2040, 1, 1), Date(2040, 12, 31))]
        ops = [
            [DateTime(2030, 1, 1, 0), DateTime(2030, 1, 1, 1)],
            [DateTime(2040, 1, 1, 0), DateTime(2040, 1, 1, 1)],
        ]
        tm = PSIN.InvestmentTimeMapping(invest, ops, no_feasibility)

        @test tm isa IOM.AbstractTimeMapping
        @test IOM.get_base_date(tm) == Date(2030, 1, 1)
        @test PSIN.get_investment_time_stamps(tm) == invest
        @test IOM.get_period_count(tm) == 2
        @test PSIN.get_investment_time_steps(tm) == 1:2

        @test length(IOM.get_timestamps(tm)) == 4
        @test IOM.get_time_steps(tm) == 1:4
        @test IOM.get_total_operation_period_count(tm) == 4

        @test PSIN.get_operational_indexes(tm) == [1, 2]
        @test PSIN.is_feasibility_empty(tm)
        @test isempty(PSIN.get_feasibility_indexes(tm))
        @test PSIN.get_all_indexes(tm) == [1, 2]

        @test PSIN.get_consecutive_slices(tm) == [1:2, 3:4]
        @test PSIN.get_inverse_invest_mapping(tm) == [1, 2]
        invest_map = PSIN.get_investment_map_to_operational_slices(tm)
        @test invest_map[1] == [1]
        @test invest_map[2] == [2]

        # Generic IOM functions work on the investment mapping
        @test IOM.get_blocks(tm, 2) == [2]
        @test IOM.get_period_time_steps(tm, 1) == [1, 2]
        @test IOM.get_period_index(tm, 3) == 2
        @test IOM.get_last_time_step(tm, 1) == 2
    end

    @testset "With feasibility periods" begin
        invest = [(Date(2030, 1, 1), Date(2030, 12, 31))]
        ops = [[DateTime(2030, 1, 1, 0), DateTime(2030, 1, 1, 1)]]
        feas = [[DateTime(2030, 6, 1, 0)]]
        tm = PSIN.InvestmentTimeMapping(invest, ops, feas)

        @test !PSIN.is_feasibility_empty(tm)
        @test PSIN.get_operational_indexes(tm) == [1]
        @test PSIN.get_feasibility_indexes(tm) == [2]
        @test PSIN.get_all_indexes(tm) == [1, 2]
        @test IOM.get_total_operation_period_count(tm) == 2
        @test PSIN.get_feasibility_time_steps(tm) == 3:3
        @test IOM.get_blocks(tm, 1) == [1, 2]
    end

    @testset "Operational weights" begin
        invest = [(Date(2030, 1, 1), Date(2030, 12, 31))]
        ops = [[DateTime(2030, 1, 1, 0)], [DateTime(2030, 6, 1, 0)]]

        # Default: 1.0 per operational slice
        tm = PSIN.InvestmentTimeMapping(invest, ops, no_feasibility)
        @test PSIN.get_operational_weights(tm) == [1.0, 1.0]

        # Feasibility slices weigh 0.0 and follow the operational slices
        feas = [[DateTime(2030, 9, 1, 0)]]
        tm_w =
            PSIN.InvestmentTimeMapping(invest, ops, feas; operational_weights=[90.0, 275.0])
        @test IOM.get_block_weights(tm_w) == [90.0, 275.0, 0.0]
        w = PSIN.get_operational_weights(tm_w)
        @test [w[op_ix] for op_ix in PSIN.get_operational_indexes(tm_w)] == [90.0, 275.0]

        @test_throws ErrorException PSIN.InvestmentTimeMapping(
            invest,
            ops,
            no_feasibility;
            operational_weights=[1.0],
        )
    end

    @testset "Periods outside every investment interval are rejected" begin
        invest = [(Date(2030, 1, 1), Date(2030, 12, 31))]
        inside = [DateTime(2030, 6, 1, 0), DateTime(2030, 6, 1, 1)]
        outside = [DateTime(2031, 6, 1, 0), DateTime(2031, 6, 1, 1)]

        @test_throws r"Operational period 2 .* does not fall within any investment interval" PSIN.InvestmentTimeMapping(
            invest,
            [inside, outside],
            no_feasibility,
        )
        @test_throws r"Feasibility period 1 .* does not fall within any investment interval" PSIN.InvestmentTimeMapping(
            invest,
            [inside],
            [outside],
        )
    end
end
