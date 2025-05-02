module Processing
# src/processing.jl
using DataFrames
using Dates
using Logging
using Statistics
using .Structs # Use structs from parent module scope

export process_data

"""
    ProcessedData

A container struct holding all the processed metrics and aggregated dataframes.
"""
struct ProcessedData
    repo_metrics::Dict{String, RepoMetrics}
    contributor_metrics::Vector{ContributorMetrics} # All individual contributor metrics
    pull_request_metrics::Dict{String, PullRequestMetrics}
    commit_history::Vector{CommitHistoryEntry} # All individual commit entries
    # --- Aggregated Data ---
    contributor_summary::DataFrame # Aggregated per contributor across all repos
    overall_commit_activity::DataFrame # Aggregated commit counts per date (e.g., daily or monthly)
    overall_stats::Dict{String, Any} # Org-level summary stats
end


"""
    process_data(all_basic_info, all_issues, all_contributors, all_commits, all_pull_requests, config, logger) -> ProcessedData

Processes the raw data fetched from the GitHub API into structured metrics and aggregates.

# Arguments
- `all_basic_info::Dict{String, RepoBasicInfo}`: Raw basic info per repo.
- `all_issues::Dict{String, Vector{GitHub.Issue}}`: Raw issues per repo.
- `all_contributors::Dict{String, Vector{ContributorMetrics}}`: Raw contributors per repo.
- `all_commits::Dict{String, Vector{CommitHistoryEntry}}`: Raw commit history per repo.
- `all_pull_requests::Dict{String, Vector{GitHub.PullRequest}}`: Raw PRs per repo.
- `config::AnalyticsConfig`: The configuration object.
- `logger::AbstractLogger`: The logger instance.

# Returns
- `ProcessedData`: A struct containing dictionaries and dataframes of processed metrics.
"""
function process_data(
    all_basic_info::Dict{String, RepoBasicInfo},
    all_issues::Dict{String, Vector{GitHub.Issue}},
    all_contributors::Dict{String, Vector{ContributorMetrics}},
    all_commits::Dict{String, Vector{CommitHistoryEntry}},
    all_pull_requests::Dict{String, Vector{GitHub.PullRequest}},
    config::AnalyticsConfig,
    logger::AbstractLogger
)::ProcessedData

    @info "Starting data processing..."
    processed_repo_metrics = Dict{String, RepoMetrics}()
    processed_pr_metrics = Dict{String, PullRequestMetrics}()
    all_contrib_metrics_list = ContributorMetrics[] # Combine contributors from all repos
    all_commit_history_list = CommitHistoryEntry[] # Combine commits from all repos

    repo_names = keys(all_basic_info) # Process only repos where basic info succeeded

    for repo_name in repo_names
        @debug "Processing data for repo: $repo_name"
        basic_info = all_basic_info[repo_name]

        # --- Process Issues ---
        open_issues_count = 0
        closed_issues_count = 0
        if haskey(all_issues, repo_name)
            repo_issues = all_issues[repo_name]
            open_issues_count = count(i -> i.state == "open", repo_issues)
            closed_issues_count = length(repo_issues) - open_issues_count
        else
            @warn "No issue data found for $repo_name during processing."
        end

        # Create initial RepoMetrics object
        repo_metric = RepoMetrics(basic_info, open_issues_count, closed_issues_count)

        # --- Process Commits ---
        monthly_commits_last30d = 0
        total_commits_fetched = 0
        if config.fetch_commit_history && haskey(all_commits, repo_name)
            repo_commits = all_commits[repo_name]
            total_commits_fetched = length(repo_commits)
            append!(all_commit_history_list, repo_commits) # Add to overall list

            # Calculate commits in the last 30 days
            one_month_ago_dt = now() - Day(30) # Use DateTime for comparison
            for commit in repo_commits
                 # Use the primary date (committer or author) stored in CommitHistoryEntry
                 commit_dt = commit.committer_date != DateTime(0) ? commit.committer_date : commit.author_date
                 if commit_dt >= one_month_ago_dt
                     monthly_commits_last30d += 1
                 end
            end
            @debug "Commit counts for $repo_name" total_fetched=total_commits_fetched last_30_days=monthly_commits_last30d
        else
             @debug "No commit history data to process for $repo_name (fetch disabled or failed)."
        end
        # Update RepoMetrics (it's mutable)
        repo_metric.total_commits_fetched_period = total_commits_fetched
        repo_metric.monthly_commits_last30d = monthly_commits_last30d

        # --- Process Contributors ---
        if config.fetch_contributors && haskey(all_contributors, repo_name)
            repo_contributors = all_contributors[repo_name]
            append!(all_contrib_metrics_list, repo_contributors)
            @debug "Added $(length(repo_contributors)) contributor entries for $repo_name to overall list."
        else
             @debug "No contributor data to process for $repo_name (fetch disabled or failed)."
        end

        # --- Process Pull Requests ---
        if config.fetch_pull_requests && haskey(all_pull_requests, repo_name)
            repo_prs = all_pull_requests[repo_name]
            open_pr = 0
            closed_pr = 0
            merged_pr = 0
            merge_times_days = Float64[]

            for pr in repo_prs
                if pr.state == "open"
                    open_pr += 1
                elseif !isnothing(pr.merged_at) # Merged (check merged_at first)
                    merged_pr += 1
                    # Calculate merge time
                    try
                         created_at = DateTime(pr.created_at)
                         merged_at = DateTime(pr.merged_at)
                         duration = merged_at - created_at
                         # Filter out nonsensical durations (e.g., negative if clocks skewed?)
                         if duration >= Dates.Millisecond(0)
                             push!(merge_times_days, Dates.value(duration) / (1000 * 60 * 60 * 24)) # Milliseconds to days
                         else
                             @warn "Negative PR merge duration detected, skipping." repo=repo_name pr_number=pr.number created=created_at merged=merged_at
                         end
                    catch date_err
                         @warn "Could not parse PR dates for merge time calculation" repo=repo_name pr_number=pr.number exception=date_err
                    end
                else # Closed but not merged
                    closed_pr += 1
                end
            end

            avg_merge_time = !isempty(merge_times_days) ? round(mean(merge_times_days), digits=2) : nothing
            total_pr = open_pr + closed_pr + merged_pr

            pr_metric = PullRequestMetrics(
                repo_name, open_pr, closed_pr, merged_pr, total_pr, avg_merge_time
            )
            processed_pr_metrics[repo_name] = pr_metric
            @debug "Processed PR metrics for $repo_name" open=open_pr closed=closed_pr merged=merged_pr avg_merge_days=avg_merge_time
        else
            @debug "No PR data to process for $repo_name (fetch disabled or failed)."
            # Optionally create a default/empty PRMetrics entry? Or leave it out of the dict. Leaving out for now.
        end

        # Store the fully populated RepoMetrics
        processed_repo_metrics[repo_name] = repo_metric

    end # End loop over repos

    # --- Aggregate Contributor Summary ---
    contrib_summary_df = DataFrame(contributor_login=String[], total_commits=Int[])
    if !isempty(all_contrib_metrics_list) && config.fetch_contributors
        contrib_df = DataFrame(all_contrib_metrics_list)
        if !isempty(contrib_df)
             # Group by contributor login and sum commit counts
             grouped = groupby(contrib_df, :contributor_login)
             contrib_summary_df = combine(grouped, :commit_count => sum => :total_commits)
             sort!(contrib_summary_df, :total_commits, rev=true)
             @info "Aggregated commit counts for $(nrow(contrib_summary_df)) unique contributors."
        else
             @warn "Contributor list was not empty, but DataFrame conversion failed or resulted in empty DF."
        end
    else
        @info "No contributor data fetched or processed for summary."
    end

    # --- Aggregate Commit Activity (e.g., per day) ---
    overall_commit_df = DataFrame(date=Date[], commit_count=Int[])
    if !isempty(all_commit_history_list) && config.fetch_commit_history
        commit_counts_per_day = Dict{Date, Int}()
        for commit in all_commit_history_list
             # Use the primary date
             commit_dt = commit.committer_date != DateTime(0) ? commit.committer_date : commit.author_date
             commit_date = Date(commit_dt)
             commit_counts_per_day[commit_date] = get(commit_counts_per_day, commit_date, 0) + 1
        end
        if !isempty(commit_counts_per_day)
            # Convert dict to DataFrame
            dates = Date[]
            counts = Int[]
            for (d, c) in sort(collect(commit_counts_per_day))
                 # Filter out very old dates if processing made an error? Optional.
                 # if d >= config.since_date # Ensure only dates within the intended period are included
                    push!(dates, d)
                    push!(counts, c)
                 # end
            end
            overall_commit_df = DataFrame(date=dates, commit_count=counts)
            @info "Aggregated daily commit counts for $(nrow(overall_commit_df)) days."
        end
    else
        @info "No commit history data fetched or processed for overall activity."
    end


    # --- Calculate Overall Summary Statistics ---
    # TODO: Add more overall stats (e.g., total stars, forks, avg resolution rate)
    overall_stats = Dict{String, Any}(
         "total_repos_analyzed" => length(processed_repo_metrics),
         "total_commits_fetched_period" => sum(m.total_commits_fetched_period for m in values(processed_repo_metrics); init=0),
         "total_stars" => sum(m.stars for m in values(processed_repo_metrics); init=0),
         "total_forks" => sum(m.forks for m in values(processed_repo_metrics); init=0),
         # ... more to come
    )
    @info "Calculated basic overall statistics."


    # --- Construct the final ProcessedData object ---
    processed_data = ProcessedData(
        processed_repo_metrics,
        all_contrib_metrics_list, # Keep the raw list if needed elsewhere
        processed_pr_metrics,
        all_commit_history_list, # Keep the raw list
        contrib_summary_df,
        overall_commit_df,
        overall_stats
    )

    @info "Data processing complete."
    return processed_data
end
end#module Processing