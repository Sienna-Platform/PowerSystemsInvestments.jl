using Documenter, PowerSystemsInvestments

pages = OrderedDict(
    "Welcome Page" => "index.md",
    "Quick Start Guide" => "quick_start_guide.md",
    "Tutorials" => "tutorials/intro_page.md",
    "Public API Reference" => "api/public.md",
    "Internal API Reference" => "api/internal.md",
)

makedocs(
    modules=[PowerSystemsInvestments],
    format=Documenter.HTML(prettyurls=haskey(ENV, "GITHUB_ACTIONS")),
    sitename="PowerSystemsInvestments.jl",
    authors="Freddy Mercury, Nikola Tesla, Leonard Bernestein",
    pages=Any[p for p in pages],
)

deploydocs(
    repo="github.com/NREL-Sienna/PowerSystemsInvestments.git",
    target="build",
    branch="gh-pages",
    devbranch="master",
    devurl="dev",
    push_preview=true,
    versions=["stable" => "v^", "v#.#"],
)
