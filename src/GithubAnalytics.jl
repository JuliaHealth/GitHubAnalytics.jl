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
# Utils must be first if other files use its functions without qualification
include("utils.jl")
# Config and Structs define types used elsewhere
include("config.jl")
include("structs.jl")
# Processing needs Structs (and potentially Config)
include("processing.jl") # Defines ProcessedData struct
# Fetching needs Structs, Config, Utils
include("fetching.jl")
# Reporting needs Structs, Processing (for ProcessedData), Config, Utils
include("reporting.jl")
# Plotting needs Structs, Processing, Config, Utils, CairoMakie
include("plotting.jl")


# --- Exports ---
# Core execution function and configuration
export AnalyticsConfig, run_analysis

# Data structures (consider reducing exports later if internal details change)
export RepoBasicInfo, RepoMetrics, ContributorMetrics, CommitHistoryEntry, PullRequestMetrics
export ProcessedData # Export the container for processed results


"""
    run_analysis(config::AnalyticsConfig)

Main entry point to run the GitHub analytics process based on the provided configuration.

Fetches data, processes metrics, generates reports (CSV, Markdown), and creates plots.

# Arguments
- `config::AnalyticsConfig`: Configuration object specifying targets, authentication, output options, etc.

# Returns
- `ProcessedData`: A structure containing the results of the analysis (metrics, dataframes, etc.). Returns `nothing` if critical errors occur early on.
"""
function run_analysis(config::AnalyticsConfig)
    # 1. Setup Logging
    # Note: setup_logger is defined in utils.jl
    logger = setup_logger(config)
    # Set the global logger *within this task's context*
    # This ensures all @info, @warn etc. calls use our logger
    with_logger(logger) do
        try
            @info "Starting GitHub Analytics run" V=config.verbose config.output_dir config.targets

            # Validate config? (Could be added here or in config.jl)
            # validate_config(config)

            # Ensure output directory exists
            mkpath(config.output_dir)

            # 2. Authenticate
            auth = try
                GitHub.authenticate(config.auth_token)
            catch e
                @error "FATAL: GitHub Authentication failed. Check your token and permissions." exception=(e, catch_backtrace())
                return nothing # Stop execution
            end
            @info "GitHub authentication successful."

            # 3. Identify Repositories
            # Functions below are defined in fetching.jl
            target_repos, repo_fetch_errors = identify_target_repositories(config.targets, auth, config, logger)

            if isempty(target_repos)
                @error "No target repositories identified. Exiting."
                return nothing
            end

            # 4. Fetch Data for Each Repository
            # Function defined in fetching.jl
            fetched_data = fetch_all_repo_data(target_repos, auth, config, logger)

            # Check if any data was fetched successfully
            if isempty(fetched_data.basic_info)
                 @error "No data successfully fetched for any repository. Cannot proceed."
                 return nothing
            end

            # 5. Process Fetched Data
            # Function defined in processing.jl
            @info "Processing fetched data..."
            processing_start_time = now()
            processed_data = process_data(fetched_data, config, logger)
            processing_duration = round((now() - processing_start_time).value / 1000, digits=1)
            @info "Finished processing data in $(processing_duration)s."

            # Check if processing yielded results
            if isempty(processed_data.repo_metrics)
                @warn "Processing did not yield any repository metrics. Skipping report generation."
                # Return processed_data anyway, might contain partial results or summaries
                return processed_data
            end

            # 6. Generate Outputs (Conditional)
            @info "Generating outputs..."
            output_start_time = now()

            # Functions below are defined in reporting.jl and plotting.jl
            if config.generate_csv
                generate_csv_reports(processed_data, config.output_dir, logger)
            end

            if config.generate_markdown
                generate_markdown_summary(processed_data, config, logger)
                 # TODO: Make markdown generation more modular
            end

            if config.generate_plots
                 generate_plots(processed_data, config, logger)
                 # TODO: Refactor plots for recipes and modularity
            end

            output_duration = round((now() - output_start_time).value / 1000, digits=1)
            @info "Finished generating outputs in $(output_duration)s."
            @info "GitHub Analytics run complete. Results saved in: $(config.output_dir)"

            return processed_data # Return the processed data

        catch e
            # Catch any unhandled exceptions during the main run
             @error "An unexpected error occurred during the analysis." exception=(e, catch_backtrace())
             return nothing # Indicate failure
        # Ensure logger is restored if needed, although exiting the 'with_logger' block should handle it.
        # finally
           # global_logger(previous_logger) # If you captured the previous logger
        end # try-catch
    end # with_logger
end

# --- Helper function to consolidate repo identification ---
"""
Identifies the full list of "owner/repo" strings based on config targets.
Handles organization expansion and deduplication. Returns list and any errors encountered.
"""
function identify_target_repositories(targets::Vector{String}, auth::GitHub.Authorization, config::AnalyticsConfig, logger::AbstractLogger)
    target_repos = String[]
    fetch_errors = Dict{String, Any}() # Store errors encountered per target

    @info "Identifying target repositories..."
    unique_targets = unique(targets) # Process each unique target once

    for target in unique_targets
        if occursin('/', target) # Specific repo "owner/repo"
             @debug "Adding specific repository target: $target"
            # Optional: Check if repo exists here using GitHub.repo() ?
            # Can add overhead, fetch_all_repo_data will handle 404s anyway.
            push!(target_repos, target)
        else # Assume it's an organization name
            @info "Fetching repositories for organization: $target"
            try
                # Use the pagination helper from fetching.jl (assuming it's defined there)
                # We need the actual GitHub.jl function for repos
                org_repos_raw = fetch_paginated_data(GitHub.repos, target;
                                                    auth=auth, logger=logger,
                                                    params=Dict("type" => "public"), # Fetch only public repos
                                                    context="repos for org $target")

                if isnothing(org_repos_raw)
                    @error "Failed to fetch repository list for organization '$target'. Skipping org."
                    fetch_errors[target] = "Failed to fetch repository list"
                elseif isempty(org_repos_raw)
                    @warn "No public repositories found for organization '$target' or org doesn't exist."
                else
                    # Filter out archived/forks if needed based on config? Not currently an option.
                    repo_names = [r.full_name for r in org_repos_raw]
                    append!(target_repos, repo_names)
                    @info "Found $(length(repo_names)) public repositories for $target."
                end
            catch e
                 # This catch block might be redundant if fetch_paginated_data handles errors well
                @error "Error fetching repositories for organization '$target'. Skipping org." exception=(e, catch_backtrace())
                fetch_errors[target] = e # Record error for this target
            end
        end
        sleep(config.repo_processing_delay_sec * 0.5) # Small delay even during identification
    end

    final_repo_list = unique(target_repos) # Ensure no duplicates if specified multiple ways
    @info "Identified $(length(final_repo_list)) unique repositories to analyze." targets_provided=length(targets) unique_targets=length(unique_targets)

    return final_repo_list, fetch_errors
end

# --- Helper function to consolidate fetching loop ---
"""
    FetchedData

A container struct holding all the raw data fetched from the GitHub API.
Used as intermediate step before processing.
"""
struct FetchedData
     basic_info::Dict{String, RepoBasicInfo}
     issues::Dict{String, Vector{GitHub.Issue}}
     contributors::Dict{String, Vector{ContributorMetrics}}
     commits::Dict{String, Vector{CommitHistoryEntry}}
     pull_requests::Dict{String, Vector{GitHub.PullRequest}}
     fetch_results::Dict{String, Any} # Stores :success or error per repo
 end

"""
Fetches all requested data types for the identified list of repositories.
Handles conditional fetching based on config and error tracking per repo.
"""
function fetch_all_repo_data(target_repos::Vector{String}, auth::GitHub.Authorization, config::AnalyticsConfig, logger::AbstractLogger)

    # Initialize storage for fetched data
    all_basic_info = Dict{String, RepoBasicInfo}()
    all_issues = Dict{String, Vector{GitHub.Issue}}()
    all_contributors = Dict{String, Vector{ContributorMetrics}}()
    all_commits = Dict{String, Vector{CommitHistoryEntry}}()
    all_pull_requests = Dict{String, Vector{GitHub.PullRequest}}()
    repo_fetch_results = Dict{String, Any}() # Store :success or error per repo

    @info "Fetching data for $(length(target_repos)) repositories..."
    total_repos = length(target_repos)
    fetch_start_time = now()

    for (i, repo_name) in enumerate(target_repos)
        @info "Fetching data for repo $(i)/$(total_repos): $repo_name"
        repo_start_time = now()
        fetch_error_occurred = false # Track if *any* critical fetch fails for this repo

        try
            # --- Fetch Basic Info (Always attempt first) ---
            # Function defined in fetching.jl
            basic_info = fetch_basic_repo_info(repo_name, auth, logger)
            if isnothing(basic_info)
                 @error "Failed critical fetch (basic info) for $repo_name. Skipping further fetches for this repo."
                 repo_fetch_results[repo_name] = "Basic info fetch failed"
                 fetch_error_occurred = true # Mark as failed
                 # Continue to next repo using 'continue' inside the loop
                 continue # Skip the rest of the fetches for this repo
            else
                 all_basic_info[repo_name] = basic_info
                 @debug "Fetched basic info for $repo_name"

                 # --- Fetch Issues (Always attempt if basic info succeeded) ---
                 # Function defined in fetching.jl
                 issues = fetch_issues(repo_name, auth, logger)
                 if !isnothing(issues)
                     all_issues[repo_name] = issues
                     @debug "Fetched $(length(issues)) issues for $repo_name"
                 else
                     @warn "Could not fetch issues for $repo_name."
                     # This is not treated as a critical failure stopping other fetches
                 end
                 sleep(config.repo_processing_delay_sec * 0.2) # Small delay

                 # --- Fetch Contributors (Conditional) ---
                 if config.fetch_contributors
                     # Function defined in fetching.jl
                     contributors = fetch_contributors(repo_name, auth, logger)
                     if !isnothing(contributors)
                         all_contributors[repo_name] = contributors
                         @debug "Fetched $(length(contributors)) contributors for $repo_name"
                     else
                         @warn "Could not fetch contributors for $repo_name."
                     end
                     sleep(config.repo_processing_delay_sec * 0.2)
                 end

                 # --- Fetch Commit History (Conditional) ---
                 if config.fetch_commit_history
                     since_date = today() - Month(config.commit_history_months)
                     # Function defined in fetching.jl
                     commits = fetch_commit_history(repo_name, auth, logger; since=since_date)
                     if !isnothing(commits)
                         all_commits[repo_name] = commits
                         @debug "Fetched $(length(commits)) commits for $repo_name since $since_date"
                     else
                         # This can happen for empty repos (409 handled in fetch) or other errors
                         @warn "Could not fetch commit history for $repo_name (check for 409/empty repo warning)."
                     end
                     sleep(config.repo_processing_delay_sec * 0.2)
                 end

                 # --- Fetch Pull Requests (Conditional) ---
                 if config.fetch_pull_requests
                     # Function defined in fetching.jl
                     pull_requests = fetch_pull_requests(repo_name, auth, logger)
                     if !isnothing(pull_requests)
                         all_pull_requests[repo_name] = pull_requests
                         @debug "Fetched $(length(pull_requests)) PRs for $repo_name"
                     else
                         @warn "Could not fetch pull requests for $repo_name."
                     end
                     sleep(config.repo_processing_delay_sec * 0.2)
                 end

            end # end if basic_info exists

        catch e
            # Catch unexpected errors during the fetch sequence for a repo
            @error "Unhandled error during data fetching for repository $repo_name. Skipping." exception=(e, catch_backtrace())
            repo_fetch_results[repo_name] = e # Store the error
            fetch_error_occurred = true
        finally
             repo_duration = round((now() - repo_start_time).value / 1000, digits=1)
             @debug "Finished fetching attempts for $repo_name in $(repo_duration)s."
             # Record success only if no critical error occurred
             if !fetch_error_occurred && !haskey(repo_fetch_results, repo_name)
                 repo_fetch_results[repo_name] = :success # Mark success
             end
            # Apply main delay AFTER processing a repo
            sleep(config.repo_processing_delay_sec)
        end
    end # End loop over target_repos

    fetch_duration = round((now() - fetch_start_time).value / 1000 / 60, digits=1)
    successful_fetches = count(v -> v == :success, values(repo_fetch_results))
    failed_fetches = count(v -> v != :success, values(repo_fetch_results))
    @info "Finished fetching data." successful=$successful_fetches failed=$failed_fetches total=$total_repos duration_minutes=fetch_duration

    # Return the collected data in the FetchedData struct
    return FetchedData(
         all_basic_info,
         all_issues,
         all_contributors,
         all_commits,
         all_pull_requests,
         repo_fetch_results
     )
end



# --- Placeholders for functions defined in other files ---
# These allow the module to compile before all files are fully defined.
# They should be removed or commented out once the corresponding files are implemented.

# From utils.jl (keep if utils.jl defines it)
# function setup_logger(config::AnalyticsConfig) ... end

# From processing.jl (keep if processing.jl defines it)
# function process_data(fetched_data::FetchedData, config::AnalyticsConfig, logger::AbstractLogger)::ProcessedData ... end

# From fetching.jl (keep if fetching.jl defines them)
# function fetch_basic_repo_info(repo_name, auth, logger) ... end
# function fetch_issues(repo_name, auth, logger) ... end
# function fetch_contributors(repo_name, auth, logger) ... end
# function fetch_commit_history(repo_name, auth, logger; since) ... end
# function fetch_pull_requests(repo_name, auth, logger) ... end
# function fetch_paginated_data(func, args...; auth, logger, params, context) ... end # If helper is there

# From reporting.jl (keep if reporting.jl defines them)
# function generate_csv_reports(processed_data::ProcessedData, output_dir::String, logger::AbstractLogger) ... end
# function generate_markdown_summary(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger) ... end

# From plotting.jl (This one *should* still be a placeholder)
function generate_plots(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger)
    @warn "Plotting function 'generate_plots' is not yet fully implemented."
    # Add actual plotting calls here later
end


end # module GitHubAnalytics