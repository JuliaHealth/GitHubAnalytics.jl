# src/GitHubAnalytics.jl
module GitHubAnalytics

# Standard Libraries
using Dates
using Logging
using Statistics

# External Dependencies
using GitHub
using DataFrames
using CSV
using Parameters
using LoggingExtras
using CairoMakie # Or your chosen backend

# --- Module Includes ---
# Order matters for dependencies between files
include("utils.jl")
include("config.jl")
include("structs.jl")
include("processing.jl") # Defines ProcessedData struct
include("fetching.jl")   # Defines fetch_* and uses Structs/Config
include("reporting.jl")  # Uses ProcessedData, Structs, Config
include("plotting.jl")   # Uses ProcessedData, Structs, Config


# --- Exports ---
# Core execution function and configuration
export AnalyticsConfig, run_analysis

# Data structures (Export main results container and config struct)
export ProcessedData
# Optional: export RepoBasicInfo, RepoMetrics, ContributorMetrics, CommitHistoryEntry, PullRequestMetrics
# Only export if users are expected to interact with these directly.


"""
    run_analysis(config::AnalyticsConfig)

Main entry point to run the GitHub analytics process based on the provided configuration.

Fetches data from GitHub repositories or organizations, processes metrics,
and generates reports (CSV, Markdown) and plots in the specified output directory.

# Arguments
- `config::AnalyticsConfig`: Configuration object specifying targets, authentication, output options, etc. See `AnalyticsConfig` docstring for details.

# Returns
- `Union{ProcessedData, Nothing}`: A structure containing the results of the analysis (metrics, dataframes, etc.), or `nothing` if a critical error prevented completion (e.g., authentication failure, no repositories found). Check logs for details on warnings or non-critical errors.

# Example
```julia
using GitHubAnalytics, Logging

# Ensure GITHUB_TOKEN environment variable is set
token = ENV["GITHUB_TOKEN"]

config = AnalyticsConfig(
    targets = ["JuliaHealth", "JuliaLang/julia"], # Analyze an org and a specific repo
    auth_token = token,
    output_dir = "julia_analytics_run_$(Dates.format(now(), "yyyy-mm-dd"))",
    log_level = Logging.Info,
    fetch_contributors = true,
    generate_plots = true,
    generate_csv = true,
    generate_markdown = true
)

results = run_analysis(config)

if !isnothing(results)
    println("Analysis complete. Found metrics for $(length(results.repo_metrics)) repositories.")
    # Access results, e.g., results.contributor_summary or results.overall_stats
end
```
"""
function run_analysis(config::AnalyticsConfig)
    # 1. Setup Logging (Function defined in utils.jl)
    logger = setup_logger(config)

    # Execute core logic within the logger context
    with_logger(logger) do
        try
            @info "Starting GitHub Analytics run" targets=config.targets output_dir=config.output_dir verbose=config.verbose

            # Basic Config Validation
            if isempty(config.targets); @error "Config Error: `targets` list is empty."; return nothing; end
            if isempty(config.auth_token); @error "Config Error: `auth_token` is empty."; return nothing; end

            # Ensure output directory exists
            try mkpath(config.output_dir) catch e; @warn "Could not create output directory" path=config.output_dir error=e end

            # 2. Authenticate
            auth = try GitHub.authenticate(config.auth_token) catch e
                @error "FATAL: GitHub Authentication failed." exception=(e, catch_backtrace()); return nothing
            end
            @info "GitHub authentication successful."

            # 3. Identify Repositories (Helper function defined below)
            target_repos, repo_identify_errors = identify_target_repositories(config.targets, auth, config, logger)
            if !isempty(repo_identify_errors); @warn "Encountered errors identifying some repository targets." errors=repo_identify_errors; end
            if isempty(target_repos); @error "No target repositories successfully identified. Exiting."; return nothing; end

            # 4. Fetch Data (Helper function defined below)
            fetched_data = fetch_all_repo_data(target_repos, auth, config, logger)
            num_successful_fetches = count(v -> v == :success, values(fetched_data.fetch_results))
            if isempty(fetched_data.basic_info) || num_successful_fetches == 0
                 @error "Failed to fetch basic info for any identified repository. Cannot proceed."
                 return nothing # Or return partial ProcessedData if fetch_results are useful alone
            end

            # 5. Process Fetched Data (Function defined in processing.jl)
            @info "Processing fetched data for $num_successful_fetches repositories..."
            processing_start_time = now()
            processed_data = process_data(fetched_data, config, logger) # process_data takes FetchedData now
            processing_duration = round((now() - processing_start_time).value / 1000, digits=1)
            @info "Finished processing data in $(processing_duration)s."

            # Check if processing yielded results
            if isempty(processed_data.repo_metrics)
                @warn "Processing completed, but yielded no final repository metrics. Skipping report generation."
                return processed_data # Return partial results
            end

            # 6. Generate Outputs (Conditional)
            @info "Generating outputs..."
            output_start_time = now()
            # Functions are defined in reporting.jl and plotting.jl
            if config.generate_csv; generate_csv_reports(processed_data, config.output_dir, logger); end
            if config.generate_markdown; generate_markdown_summary(processed_data, config, logger); end
            if config.generate_plots; generate_plots(processed_data, config, logger); end # generate_plots is defined in plotting.jl
            output_duration = round((now() - output_start_time).value / 1000, digits=1)
            @info "Finished generating outputs in $(output_duration)s."

            total_repos_final = length(processed_data.repo_metrics)
            @info "GitHub Analytics run complete. Results for $total_repos_final repositories saved in: $(config.output_dir)"
            return processed_data # Return final results

        catch e
             @error "An unexpected error terminated the analysis." exception=(e, catch_backtrace())
             return nothing # Indicate failure
        end # try-catch
    end # with_logger
end


# --- Internal Helper Structs ---
# (Defined here for clarity as they are primarily used within run_analysis flow)

"""
    FetchedData

(Internal helper struct) Container for raw fetched data.
"""
struct FetchedData
     basic_info::Dict{String, RepoBasicInfo}
     issues::Dict{String, Vector{<:GitHub.GitHubType}} # Use abstract type for issues/prs
     contributors::Dict{String, Vector{ContributorMetrics}}
     commits::Dict{String, Vector{CommitHistoryEntry}}
     pull_requests::Dict{String, Vector{<:GitHub.GitHubType}} # Use abstract type
     fetch_results::Dict{String, Any} # :success or error
 end


# --- Internal Helper Functions ---

"""
    identify_target_repositories(...)

(Internal helper) Identifies the full list of "owner/repo" strings based on config targets.
"""
function identify_target_repositories(targets::Vector{String}, auth::GitHub.Authorization, config::AnalyticsConfig, logger::AbstractLogger)
    target_repos = String[]
    fetch_errors = Dict{String, Any}()
    @info "Identifying target repositories..."
    unique_targets = unique(targets)

    for target in unique_targets
        if occursin('/', target)
            @debug "Adding specific repository target: $target"
            push!(target_repos, target)
        else # Organization
            @info "Fetching repositories for organization: $target"
            # fetch_paginated_data is defined in fetching.jl
            org_repos_raw = fetch_paginated_data(GitHub.repos, target; auth=auth, logger=logger, params=Dict("type" => "public"), context="repos for org $target")

            if isnothing(org_repos_raw)
                @error "Failed to fetch repository list for organization '$target'. Skipping org."
                fetch_errors[target] = "Failed to fetch repository list (check logs)"
            elseif isempty(org_repos_raw)
                @warn "No public repositories found for organization '$target' or org doesn't exist."
            else
                repo_names = [r.full_name for r in org_repos_raw if !isnothing(r.full_name)]
                append!(target_repos, repo_names)
                @info "Found $(length(repo_names)) public repositories for $target."
            end
        end
        sleep(config.repo_processing_delay_sec * 0.5)
    end

    final_repo_list = unique(target_repos)
    @info "Identified $(length(final_repo_list)) unique repositories to analyze." targets_provided=length(targets) unique_targets=length(unique_targets)
    return final_repo_list, fetch_errors
end


"""
    fetch_all_repo_data(...)

(Internal helper) Fetches all requested data types for the identified repositories.
"""
function fetch_all_repo_data(target_repos::Vector{String}, auth::GitHub.Authorization, config::AnalyticsConfig, logger::AbstractLogger)::FetchedData
    # Initialize storage
    all_basic_info = Dict{String, RepoBasicInfo}()
    all_issues = Dict{String, Vector{GitHub.Issue}}() # Correct type
    all_contributors = Dict{String, Vector{ContributorMetrics}}()
    all_commits = Dict{String, Vector{CommitHistoryEntry}}()
    all_pull_requests = Dict{String, Vector{GitHub.PullRequest}}() # Correct type
    repo_fetch_results = Dict{String, Any}()

    @info "Fetching data for $(length(target_repos)) repositories..."
    total_repos = length(target_repos); fetch_start_time = now()

    for (i, repo_name) in enumerate(target_repos)
        @info "Fetching data for repo $(i)/$(total_repos): $repo_name"
        repo_start_time = now(); fetch_error_occurred = false

        try
            # --- Fetch Basic Info (Critical) ---
            basic_info = fetch_basic_repo_info(repo_name, auth, logger) # Defined in fetching.jl
            if isnothing(basic_info)
                 @error "Failed critical fetch (basic info) for $repo_name. Skipping."
                 repo_fetch_results[repo_name] = "Basic info fetch failed"
                 fetch_error_occurred = true; continue
            else
                 all_basic_info[repo_name] = basic_info
                 @debug "Fetched basic info for $repo_name"

                 # --- Fetch Issues (Non-critical) ---
                 issues_result = fetch_issues(repo_name, auth, logger) # Defined in fetching.jl
                 if !isnothing(issues_result); all_issues[repo_name] = issues_result
                 else; @warn "Could not fetch issues for $repo_name."; end
                 sleep(config.repo_processing_delay_sec * 0.1)

                 # --- Fetch Contributors (Conditional, Non-critical) ---
                 if config.fetch_contributors
                     contrib_result = fetch_contributors(repo_name, auth, logger) # Defined in fetching.jl
                     if !isnothing(contrib_result); all_contributors[repo_name] = contrib_result
                     else; @warn "Could not fetch contributors for $repo_name."; end
                     sleep(config.repo_processing_delay_sec * 0.1)
                 end

                 # --- Fetch Commit History (Conditional, Non-critical) ---
                 if config.fetch_commit_history
                     since_date = today() - Month(config.commit_history_months)
                     commits_result = fetch_commit_history(repo_name, auth, logger; since=since_date) # Defined in fetching.jl
                     if !isnothing(commits_result); all_commits[repo_name] = commits_result
                     else; @warn "Could not fetch commit history for $repo_name."; end
                     sleep(config.repo_processing_delay_sec * 0.1)
                 end

                 # --- Fetch Pull Requests (Conditional, Non-critical) ---
                 if config.fetch_pull_requests
                     prs_result = fetch_pull_requests(repo_name, auth, logger) # Defined in fetching.jl
                     if !isnothing(prs_result); all_pull_requests[repo_name] = prs_result
                     else; @warn "Could not fetch pull requests for $repo_name."; end
                     sleep(config.repo_processing_delay_sec * 0.1)
                 end
            end # basic_info check

        catch e
            @error "Unhandled error fetching data sequence for $repo_name." exception=(e, catch_backtrace())
            repo_fetch_results[repo_name] = e; fetch_error_occurred = true
        finally
             repo_duration = round((now() - repo_start_time).value / 1000, digits=1)
             @debug "Finished fetch attempts for $repo_name in $(repo_duration)s."
             if !fetch_error_occurred && !haskey(repo_fetch_results, repo_name); repo_fetch_results[repo_name] = :success; end
             sleep(config.repo_processing_delay_sec) # Main delay after repo attempt
        end
    end # End loop over target_repos

    fetch_duration = round((now() - fetch_start_time).value / 1000 / 60, digits=1)
    successful_fetches = count(v -> v == :success, values(repo_fetch_results))
    failed_or_skipped = total_repos - successful_fetches
    @info "Finished fetching data." successful_repos=$successful_fetches failed_or_skipped_repos=$failed_or_skipped total_identified=$total_repos duration_minutes=fetch_duration

    # Explicitly cast Dictionaries to expected types for FetchedData constructor if needed,
    # though usually inference works. Using correct types in initialization is better.
    return FetchedData(
         all_basic_info, all_issues, all_contributors, all_commits,
         all_pull_requests, repo_fetch_results
     )
end


end # module GitHubAnalytics