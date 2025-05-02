# src/config.jl
module Configs
using Parameters, Logging, Dates

export AnalyticsConfig # Export it so users can create it

"""
    AnalyticsConfig

Configuration settings for the GitHub analytics process.

# Fields
- `targets::Vector{String}`: A list of GitHub organizations (e.g., `"JuliaHealth"`) or specific repositories (e.g., `"JuliaLang/julia"`) to analyze.
- `auth_token::String`: Your GitHub Personal Access Token (PAT). *Required*.
- `output_dir::String`: Directory where output files (CSV, plots, Markdown) will be saved. Defaults to `"github_analytics_output"`.
- `max_repos_in_plots::Int`: Maximum number of repositories to show in bar plots (e.g., top N by stars). Defaults to 15.
- `commit_history_months::Int`: How many months of commit history to fetch. Defaults to 12.
- `repo_processing_delay_sec::Float64`: A small delay (in seconds) between processing repositories to avoid hitting API rate limits aggressively. Defaults to 0.2.
- `log_level::LogLevel`: Minimum log level to output (e.g., `Logging.Info`, `Logging.Debug`). Defaults to `Logging.Info`.
- `verbose::Bool`: If true, sets log level to Debug, overriding `log_level`. Defaults to `false`.
- `fetch_contributors::Bool`: Whether to fetch contributor statistics (can be slow for large repos/orgs). Defaults to `true`.
- `fetch_commit_history::Bool`: Whether to fetch commit history. Defaults to `true`.
- `fetch_pull_requests::Bool`: Whether to fetch pull request details. Defaults to `true`.
- `generate_plots::Bool`: Whether to generate plots. Defaults to `true`.
- `generate_csv::Bool`: Whether to generate CSV output files. Defaults to `true`.
- `generate_markdown::Bool`: Whether to generate a Markdown summary file. Defaults to `true`.
"""
@with_kw mutable struct AnalyticsConfig
    targets::Vector{String}
    auth_token::String
    output_dir::String = "github_analytics_output"
    max_repos_in_plots::Int = 15
    commit_history_months::Int = 12
    repo_processing_delay_sec::Float64 = 0.2
    log_level::LogLevel = Logging.Info
    verbose::Bool = false
    # --- Control Switches ---
    fetch_contributors::Bool = true
    fetch_commit_history::Bool = true
    fetch_pull_requests::Bool = true
    generate_plots::Bool = true
    generate_csv::Bool = true
    generate_markdown::Bool = true

    # Internal derived fields (consider if needed later, maybe better handled outside config)
    # since_date::Date = today() - Month(commit_history_months) # Example, might compute this elsewhere
end

# You might add validation or processing functions here later if needed
# function validate_config(config::AnalyticsConfig)
#     !isempty(config.targets) || throw(ArgumentError("`targets` list cannot be empty."))
#     !isempty(config.auth_token) || throw(ArgumentError("`auth_token` cannot be empty."))
#     config.max_repos_in_plots > 0 || throw(ArgumentError("`max_repos_in_plots` must be positive."))
#     # ... more checks
# end

end#module Configs