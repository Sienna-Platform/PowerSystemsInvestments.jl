struct MpiInfo
    comm::Any
    rank::Int
    root::Bool
    nprocs::Int

    function MpiInfo(comm)
        rank = MPI.Comm_rank(comm) + 1
        is_root = (rank == 1)
        nprocs = MPI.Comm_size(comm)
        return new(comm, rank, is_root, nprocs)
    end
end
