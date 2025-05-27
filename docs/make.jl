using Documenter, DocumenterVitepress

makedocs(; 
    sitename = "GitHubAnalytics.jl", 
    authors = "Divyansh Goyal <divital2004@gmail.com>",
    format=DocumenterVitepress.MarkdownVitepress(
        repo = "github.com/JuliaHealth/GitHubAnalytics.jl", 
        devbranch = "main",
        devurl = "dev",
    ),
    warnonly = true,
    draft = false,
    source = "src",
    build = "build",
    pages=[
        "Manual" => [
            "Get Started" => "manual/get_started.md",
            "Code" => "manual/code_example.md"
        ],
        "api" => "api.md"
        ],
)

# This is the critical part that creates the version structure
DocumenterVitepress.deploydocs(;
    repo = "github.com/JuliaHealth/GitHubAnalytics.jl", 
    devbranch = "main",
    push_preview = true,
)
