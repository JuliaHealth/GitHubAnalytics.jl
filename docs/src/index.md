```@raw html
---
layout: home

hero:
  name: "GitHubAnalytics.jl"
  text: "Comprehensive GitHub Repository Analytics"
  tagline: Julia package for analyzing GitHub repositories and organizations with powerful insights and visualizations
  image:
    src: /logo.png
    alt: GitHubAnalytics.jl Graphic
  actions:
    - theme: brand
      text: View on GitHub 
      link: https://github.com/JuliaHealth/GitHubAnalytics.jl
    - theme: alt
      text: Get Started
      link: /manual/get_started

features:
  - icon: 📊
    title: Repository Analysis
    details: Analyze stars, forks, issues, pull requests, and commit history across repositories
  - icon: 🏢
    title: Organization-Wide Insights
    details: Aggregate metrics across multiple repositories for comprehensive organizational analysis
  - icon: 👥
    title: Contributor Analysis
    details: Identify top contributors and analyze contribution patterns with detailed metrics
  - icon: ⏱️
    title: Issue Management Metrics
    details: Track resolution rates, time-to-close statistics, and issue management efficiency
  - icon: 📈
    title: Powerful Visualizations
    details: Generate charts for repository activity, language distributions, trends, and more
  - icon: 📝
    title: Flexible Output
    details: Export data as CSV files, markdown reports, and publication-ready visualizations
---
```

````@raw html
<div class="vp-doc" style="width:80%; margin:auto">

<p style="margin-bottom:2cm"></p>

<h1>What is GitHubAnalytics.jl?</h1>

GitHubAnalytics.jl is a comprehensive Julia package that provides deep insights into GitHub repositories and organizations. It fetches data from the GitHub API, processes metrics about repository activity, and generates visualizations and reports to help you understand repository health and contribution patterns.

<h2>Key Features</h2>

- **Repository Analysis**: Comprehensive analysis of stars, forks, issues, pull requests, and commit history
- **Organization-Wide Insights**: Aggregate metrics across multiple repositories for organizational overview
- **Contributor Analysis**: Identify top contributors and analyze contribution patterns
- **Issue Management**: Track resolution rates, time-to-close statistics, and management efficiency
- **Temporal Analysis**: Analyze trends in issue resolution time and commit activity over time
- **Rich Visualizations**: Generate professional charts and plots for presentations and reports
- **Multiple Output Formats**: CSV data files, markdown reports, and publication-ready visualizations

<h2>Quick Start</h2>

1. Install GitHubAnalytics.jl in your Julia environment:

```julia
using Pkg
Pkg.develop("https://github.com/JuliaHealth/GitHubAnalytics.jl")
```

2. Set up your GitHub token and run analysis:

```julia
using GitHubAnalytics
using Logging

# Set your GitHub token (required for API access)
token = ENV["GITHUB_TOKEN"]

# Create configuration
config = AnalyticsConfig(
    targets = ["JuliaLang", "JuliaLang/julia"],  # Organizations and repositories to analyze
    auth_token = token,
    output_dir = "github_analysis_results",
    fetch_contributors = true, 
    fetch_commit_history = true,
    fetch_pull_requests = true,
    generate_plots = true,
    generate_csv = true,
    generate_markdown = true
)

# Run the analysis
results = run_analysis(config)
```

<h2>Example Outputs</h2>

GitHubAnalytics.jl generates a variety of visualizations and reports:

- **Issue Analysis**: Distribution and trend analysis of issue resolution times
- **Repository Metrics**: Stars, forks, and activity comparisons
- **Contributor Insights**: Top contributor identification and contribution patterns  
- **Language Distribution**: Programming language usage across repositories
- **Pull Request Metrics**: Merge rates and review time analysis
- **Temporal Trends**: Time-based analysis of repository activity

<h2>Use Cases</h2>

- **Project Maintainers**: Monitor repository health and contributor activity
- **Organization Leaders**: Get insights into development productivity across teams
- **Researchers**: Analyze open source development patterns and trends
- **Community Managers**: Track engagement and identify key contributors
- **Decision Makers**: Data-driven insights for resource allocation and project prioritization

<div style="text-align: center; margin-top: 4rem; padding: 2rem 0; border-top: 1px solid #eaecef; color: #4e6e8e;">
© 2025 Divyansh Goyal | GitHubAnalytics.jl Documentation
</div>

</div>
````