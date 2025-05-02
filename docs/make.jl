using GithubAnalytics
using Documenter

DocMeta.setdocmeta!(GithubAnalytics, :DocTestSetup, :(using GithubAnalytics); recursive=true)

makedocs(;
    modules=[GithubAnalytics],
    authors="JuliaHealth",
    sitename="GithubAnalytics.jl",
    format=Documenter.HTML(;
        canonical="https://divital-coder.github.io/GithubAnalytics.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/divital-coder/GithubAnalytics.jl",
    devbranch="main",
)
