using Documenter, PowerSystemsInvestments
import DataStructures: OrderedDict
using Literate

# Generates docs/src/tutorials/generated_*.md and *.ipynb from the Literate scripts
include(joinpath(@__DIR__, "make_tutorials.jl"))
make_tutorials()

pages = OrderedDict(
    "Welcome Page" => "index.md",
    "Tutorials" => Any[
        "Build and Solve a Capacity Expansion Model" => "tutorials/generated_first_capacity_expansion.md",
        "Add Storage, Regions, and Transmission" => "tutorials/generated_multi_region_expansion.md",
    ],
    "How to..." => Any[
        "...assign formulations to technologies" => "how_to/assign_formulations.md",
        "...define investment periods and representative days" => "how_to/define_time_structure.md",
        "...model multiple regions and transmission" => "how_to/model_multiple_regions.md",
        "...make discrete investment decisions" => "how_to/discrete_investments.md",
        "...limit hydro energy with a budget" => "how_to/hydro_energy_budget.md",
        "...add an energy share requirement" => "how_to/add_energy_share_requirement.md",
        "...read the results" => "how_to/read_results.md",
        "...configure the solver and logging" => "how_to/configure_solver_logging.md",
        "...debug an infeasible model" => "how_to/debug_infeasible_model.md",
    ],
    "Explanation" => Any[
        "explanation/psinv_structure.md",
        "explanation/formulation_axes.md",
        "explanation/time_representation.md",
        "explanation/cost_accounting.md",
        "explanation/build_process.md",
    ],
    "Reference" => Any[
        "Public API" => "api/public.md",
        "Formulation Library" => Any[
            "Introduction" => "formulation_library/introduction.md",
            "Objective Function" => "formulation_library/objective.md",
            "Supply Technologies" => "formulation_library/supply.md",
            "Storage Technologies" => "formulation_library/storage.md",
            "Co-located Technologies" => "formulation_library/colocated.md",
            "Demand" => "formulation_library/demand.md",
            "Transport Technologies" => "formulation_library/transport.md",
            "Energy Balance" => "formulation_library/energy_balance.md",
            "Requirements" => "formulation_library/requirements.md",
        ],
        "Time Series Names" => "api/time_series_names.md",
        "Implementation Status" => "api/implementation_status.md",
        "Glossary and Acronyms" => "api/glossary.md",
        "Developers" => [
            "Developer Guidelines" => "api/developer_guidelines.md",
            "Internals" => "api/internal.md",
        ],
    ],
)

makedocs(;
    modules=[PowerSystemsInvestments],
    format=Documenter.HTML(;
        prettyurls=haskey(ENV, "GITHUB_ACTIONS"),
        size_threshold=nothing,
    ),
    sitename="PowerSystemsInvestments.jl",
    authors="Jose Daniel Lara, Rodrigo Henriquez-Auba, and Contributors",
    pages=Any[p for p in pages],
    draft=false,
)

deploydocs(;
    repo="github.com/Sienna-Platform/PowerSystemsInvestments.jl.git",
    target="build",
    branch="gh-pages",
    devbranch="main",
    devurl="dev",
    push_preview=true,
    versions=["stable" => "v^", "v#.#"],
)
