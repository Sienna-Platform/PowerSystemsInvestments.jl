using Documenter, SIIP - PACKAGE

pages = OrderedDict(
    "Welcome Page" => "index.md",
    "Quick Start Guide" => "quick_start_guide.md",
    "Tutorials" => "tutorials/intro_page.md",
    "Public API Reference" => "api/public.md",
    "Internal API Reference" => "api/internal.md",
)

makedocs(
    modules=[SIIP-PACKAGE],
    format=Documenter.HTML(prettyurls=haskey(ENV, "GITHUB_ACTIONS")),
    sitename="SIIP-PACKAGE.jl",
    authors="Freddy Mercury, Nikola Tesla, Leonard Bernestein",
    pages=Any[p for p in pages],
)

deploydocs(
    repo="github.com/NREL-SIIP/SIIP-PACKAGE.git",
    target="build",
    branch="gh-pages",
    devbranch="master",
    devurl="dev",
    push_preview=true,
    versions=["stable" => "v^", "v#.#"],
)
