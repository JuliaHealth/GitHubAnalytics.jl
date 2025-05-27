# src/processing.jl
using DataFrames
using Dates
using Logging
using Statistics

"""
    ProcessedData

A container struct holding all the processed metrics and aggregated dataframes.
"""
struct ProcessedData
    # Input Config used
    config::AnalyticsConfig # Store config for context

    # Per-Repository Metrics
    repo_metrics::Dict{String, RepoMetrics}
    pull_request_metrics::Dict{String, PullRequestMetrics}

    # Raw underlying data (optional to include, could be large)
    # contributor_metrics_raw::Vector{ContributorMetrics}
    # commit_history_raw::Vector{CommitHistoryEntry}

    # Aggregated Data & Summaries
    contributor_summary::DataFrame # Aggregated per contributor across all repos
    overall_commit_activity::DataFrame # Aggregated commit counts per date
    language_distribution::DataFrame # Count per primary language
    overall_stats::Dict{String, Any} # Org-level summary stats (totals, averages)
    
    # Issue close time distribution data
    issue_close_times::DataFrame # Data on how long it takes to close issues

    # Store Fetch Results/Errors for reference
    fetch_results::Dict{String, Any}
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
    fetched_data::FetchedData, # Use FetchedData struct defined in GitHubAnalytics.jl
    config::AnalyticsConfig,
    logger::AbstractLogger
)::ProcessedData

    @info "Starting data processing..."
    processed_repo_metrics = Dict{String, RepoMetrics}()
    processed_pr_metrics = Dict{String, PullRequestMetrics}()
    all_contrib_metrics_list = ContributorMetrics[]
    all_commit_history_list = CommitHistoryEntry[]
    language_counts = Dict{Union{String, Nothing}, Int}()
    
    # Initialize issue close time tracking
    issue_close_times_data = DataFrame(
        repo_name = String[],
        issue_number = Int[],
        close_time_days = Float64[],
        closed_at = DateTime[]
    )

    # Process only repos where basic info succeeded
    repo_names_processed = keys(fetched_data.basic_info)

    for repo_name in repo_names_processed
        @debug "Processing data for repo: $repo_name"
        basic_info = fetched_data.basic_info[repo_name]

        # Tally Language
        lang = basic_info.primary_language
        language_counts[lang] = get(language_counts, lang, 0) + 1

        # --- Process Issues ---
        open_issues_count = 0
        closed_issues_count = 0
        if haskey(fetched_data.issues, repo_name)
            repo_issues = fetched_data.issues[repo_name]
            # Ensure issues is a vector before processing
            if isa(repo_issues, Vector{GitHub.Issue})
                open_issues_count = count(i -> i.state == "open", repo_issues)
                closed_issues_count = length(repo_issues) - open_issues_count
                
                # Calculate issue close times for closed issues
                for issue in repo_issues
                    if issue.state == "closed" && !isnothing(issue.closed_at) && !isnothing(issue.created_at)
                        try
                            created_at = DateTime(issue.created_at)
                            closed_at = DateTime(issue.closed_at)
                            
                            # Calculate time to close in days
                            close_time_days = (closed_at - created_at).value / (1000 * 60 * 60 * 24)
                            
                            # Only include positive close times (avoid data errors)
                            if close_time_days >= 0
                                push!(issue_close_times_data, (
                                    repo_name,
                                    issue.number,
                                    close_time_days,
                                    closed_at
                                ))
                            else
                                @warn "Negative issue close time for $(repo_name)#$(issue.number): $(close_time_days) days"
                            end
                        catch e
                            @warn "Error calculating close time for issue" repo=repo_name issue=issue.number exception=e
                        end
                    end
                end
            else
                @warn "Issue data for $repo_name is not a Vector{GitHub.Issue}, skipping issue processing." issues_data_type=typeof(repo_issues)
            end
        else
            @warn "No issue data found for $repo_name during processing."
        end

        # Create initial RepoMetrics object
        # RepoMetrics defined in structs.jl (included before this)
        repo_metric = RepoMetrics(basic_info, open_issues_count, closed_issues_count)

        # --- Process Commits ---
        monthly_commits_last30d = 0
        total_commits_fetched = 0
        if config.fetch_commit_history && haskey(fetched_data.commits, repo_name)
            repo_commits = fetched_data.commits[repo_name]
            if isa(repo_commits, Vector{CommitHistoryEntry})
                total_commits_fetched = length(repo_commits)
                append!(all_commit_history_list, repo_commits)

                one_month_ago_dt = now(UTC) - Day(30) # Use UTC for consistency
                for commit in repo_commits
                    commit_dt = commit.committer_date != DateTime(0) ? commit.committer_date : commit.author_date
                    # Ensure commit date has timezone for comparison with now(UTC)
                    # Note: GitHub API usually provides timezone offset 'Z' or +/-HHMM
                    # DateTime constructor should handle this. If not, explicit conversion needed.
                    try
                        # Assuming DateTime correctly parses timezone or defaults sensibly
                         if commit_dt >= one_month_ago_dt
                              monthly_commits_last30d += 1
                         end
                    catch e
                         @warn "Error comparing commit date with threshold" repo=repo_name sha=commit.sha commit_dt=commit_dt exception=e
                         # Handle case where DateTime parsing might have failed earlier
                    end
                end
                @debug "Commit counts for $repo_name" total_fetched=total_commits_fetched last_30_days=monthly_commits_last30d
            else
                 @warn "Commit data for $repo_name is not a Vector{CommitHistoryEntry}, skipping commit processing." commit_data_type=typeof(repo_commits)
            end
        else
             @debug "No commit history data to process for $repo_name (fetch disabled or failed/skipped)."
        end
        repo_metric.total_commits_fetched_period = total_commits_fetched
        repo_metric.monthly_commits_last30d = monthly_commits_last30d

        # --- Process Contributors ---
        if config.fetch_contributors && haskey(fetched_data.contributors, repo_name)
            repo_contributors = fetched_data.contributors[repo_name]
             if isa(repo_contributors, Vector{ContributorMetrics})
                append!(all_contrib_metrics_list, repo_contributors)
                @debug "Added $(length(repo_contributors)) contributor entries for $repo_name to overall list."
             else
                 @warn "Contributor data for $repo_name is not a Vector{ContributorMetrics}, skipping." contrib_data_type=typeof(repo_contributors)
             end
        else
             @debug "No contributor data to process for $repo_name (fetch disabled or failed/skipped)."
        end

        # --- Process Pull Requests ---
        if config.fetch_pull_requests && haskey(fetched_data.pull_requests, repo_name)
            repo_prs = fetched_data.pull_requests[repo_name]
             if isa(repo_prs, Vector{GitHub.PullRequest})
                open_pr = 0
                closed_pr = 0
                merged_pr = 0
                merge_times_days = Float64[]

                for pr in repo_prs
                    if pr.state == "open"
                        open_pr += 1
                    elseif !isnothing(pr.merged_at)
                        merged_pr += 1
                        try
                            created_at = DateTime(pr.created_at)
                            merged_at = DateTime(pr.merged_at)
                            duration = merged_at - created_at
                            if duration >= Dates.Millisecond(0)
                                push!(merge_times_days, Dates.value(duration) / (1000 * 60 * 60 * 24))
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

                # PullRequestMetrics defined in structs.jl
                pr_metric = PullRequestMetrics(repo_name, open_pr, closed_pr, merged_pr, total_pr, avg_merge_time)
                processed_pr_metrics[repo_name] = pr_metric
                @debug "Processed PR metrics for $repo_name" open=open_pr closed=closed_pr merged=merged_pr avg_merge_days=avg_merge_time
             else
                  @warn "Pull request data for $repo_name is not a Vector{GitHub.PullRequest}, skipping." pr_data_type=typeof(repo_prs)
             end
        else
            @debug "No PR data to process for $repo_name (fetch disabled or failed/skipped)."
        end

        processed_repo_metrics[repo_name] = repo_metric
    end # End loop over repos

    # --- Aggregate Contributor Summary ---
    contrib_summary_df = DataFrame(contributor_login=String[], total_commits=Int[])
    if !isempty(all_contrib_metrics_list) && config.fetch_contributors
        try
            contrib_df = DataFrame(all_contrib_metrics_list) # Convert list of structs
            if !isempty(contrib_df) && ncol(contrib_df) > 0 # Check if DF creation succeeded
                grouped = groupby(contrib_df, :contributor_login)
                contrib_summary_df = combine(grouped, :commit_count => sum => :total_commits)
                sort!(contrib_summary_df, :total_commits, rev=true)
                @info "Aggregated commit counts for $(nrow(contrib_summary_df)) unique contributors."
            else
                 @warn "Contributor list was not empty, but DataFrame conversion resulted in an empty or invalid DataFrame." df_size=size(contrib_df)
            end
        catch e
             @error "Error creating or processing contributor DataFrame" exception=(e, catch_backtrace())
        end
    else
        @info "No contributor data available for summary."
    end

    # --- Aggregate Commit Activity ---
    overall_commit_df = DataFrame(date=Date[], commit_count=Int[])
    if !isempty(all_commit_history_list) && config.fetch_commit_history
        commit_counts_per_day = Dict{Date, Int}()
        for commit in all_commit_history_list
            commit_dt = commit.committer_date != DateTime(0) ? commit.committer_date : commit.author_date
             if commit_dt != DateTime(0) # Avoid placeholder date
                commit_date = Date(commit_dt)
                commit_counts_per_day[commit_date] = get(commit_counts_per_day, commit_date, 0) + 1
             else
                 @warn "Skipping commit with zero date in aggregation" repo=commit.repo_name sha=commit.sha
             end
        end
        if !isempty(commit_counts_per_day)
            dates = Date[]
            counts = Int[]
            for (d, c) in sort(collect(commit_counts_per_day))
                push!(dates, d)
                push!(counts, c)
            end
            overall_commit_df = DataFrame(date=dates, commit_count=counts)
            @info "Aggregated daily commit counts for $(nrow(overall_commit_df)) days."
        end
    else
        @info "No commit history data available for overall activity."
    end

    # --- Aggregate Language Distribution ---
    lang_df = DataFrame(language=String[], count=Int[])
    if !isempty(language_counts)
        langs = String[]
        counts = Int[]
        for (lang, count) in language_counts
            push!(langs, isnothing(lang) ? "N/A" : lang)
            push!(counts, count)
        end
        lang_df = DataFrame(language=langs, count=counts)
        sort!(lang_df, :count, rev=true)
        @info "Aggregated language distribution for $(nrow(lang_df)) languages."
    end

    # --- Calculate Overall Summary Statistics ---
    total_repos_analyzed = length(processed_repo_metrics)
    total_stars = sum(m.stars for m in values(processed_repo_metrics); init=0)
    total_forks = sum(m.forks for m in values(processed_repo_metrics); init=0)
    total_open_issues = sum(m.open_issues for m in values(processed_repo_metrics); init=0)
    total_closed_issues = sum(m.closed_issues for m in values(processed_repo_metrics); init=0)
    total_issues = total_open_issues + total_closed_issues
    overall_resolution_rate = if total_issues > 0
        round(total_closed_issues / total_issues * 100, digits=1)
    else
        NaN # Use NaN for undefined rate
    end
    total_open_pr = sum(p.open_pr_count for p in values(processed_pr_metrics); init=0)
    total_merged_pr = sum(p.merged_pr_count for p in values(processed_pr_metrics); init=0)
    total_closed_pr = sum(p.closed_pr_count for p in values(processed_pr_metrics); init=0)
    total_prs = total_open_pr + total_merged_pr + total_closed_pr

    overall_stats = Dict{String, Any}(
         "total_repos_analyzed" => total_repos_analyzed,
         "total_commits_fetched_period" => sum(m.total_commits_fetched_period for m in values(processed_repo_metrics); init=0),
         "total_stars" => total_stars,
         "total_forks" => total_forks,
         "total_issues" => total_issues,
         "total_open_issues" => total_open_issues,
         "total_closed_issues" => total_closed_issues,
         "overall_issue_resolution_rate_percent" => overall_resolution_rate,
         "total_prs" => total_prs,
         "total_open_prs" => total_open_pr,
         "total_merged_prs" => total_merged_pr,
         "total_closed_prs" => total_closed_pr,
    )
    @info "Calculated overall statistics."

    # After the aggregation of all data, log the issue close time stats
    if !isempty(issue_close_times_data)
        issue_stats = Dict{String, Any}()
        issue_stats["total_closed_issues_with_data"] = nrow(issue_close_times_data)
        issue_stats["mean_close_time_days"] = mean(issue_close_times_data.close_time_days)
        issue_stats["median_close_time_days"] = median(issue_close_times_data.close_time_days)
        issue_stats["max_close_time_days"] = maximum(issue_close_times_data.close_time_days)
        issue_stats["min_close_time_days"] = minimum(issue_close_times_data.close_time_days)
        
        # Add percentiles
        issue_stats["p25_close_time_days"] = quantile(issue_close_times_data.close_time_days, 0.25)
        issue_stats["p75_close_time_days"] = quantile(issue_close_times_data.close_time_days, 0.75)
        issue_stats["p90_close_time_days"] = quantile(issue_close_times_data.close_time_days, 0.90)
        
        @info "Issue close time statistics calculated" stats=issue_stats
    else
        @info "No issue close time data available for analysis"
    end
    
    # --- Create Overall Stats ---
    overall_stats = Dict{String, Any}()
    # Total repos successfully processed
    overall_stats["total_repos_processed"] = length(processed_repo_metrics)
    # Total issues (open and closed)
    overall_stats["total_issues"] = sum(r.total_issues for r in values(processed_repo_metrics))
    overall_stats["total_open_issues"] = sum(r.open_issues for r in values(processed_repo_metrics))
    overall_stats["total_closed_issues"] = sum(r.closed_issues for r in values(processed_repo_metrics))
    # Issue resolution rate across all repos
    if overall_stats["total_issues"] > 0
        overall_stats["overall_issue_resolution_rate"] = overall_stats["total_closed_issues"] / overall_stats["total_issues"]
    else
        overall_stats["overall_issue_resolution_rate"] = nothing
    end
    
    # --- Prepare Language Distribution DataFrame ---
    lang_df = DataFrame(language = String[], count = Int[])
    for (lang, count) in language_counts
        if isnothing(lang)
            push!(lang_df, ("Unknown", count))
        else
            push!(lang_df, (lang, count))
        end
    end
    sort!(lang_df, :count, rev=true)

    # --- Prepare Overall Commit Activity DataFrame ---
    commit_activity_df = DataFrame(date = Date[], commit_count = Int[])
    if !isempty(all_commit_history_list)
        # Extract all dates with commit activity
        commit_dates = [Date(c.committer_date) for c in all_commit_history_list if c.committer_date != DateTime(0)]
        date_counts = Dict{Date, Int}()
        for date in commit_dates
            date_counts[date] = get(date_counts, date, 0) + 1
        end
        
        # Convert to sorted DataFrame
        for (date, count) in date_counts
            push!(commit_activity_df, (date, count))
        end
        sort!(commit_activity_df, :date)
    end

    # --- Construct the final ProcessedData object ---
    processed_data = ProcessedData(
        config, # Store config
        processed_repo_metrics,
        processed_pr_metrics,
        # all_contrib_metrics_list, # Decide if raw lists are needed
        # all_commit_history_list,  # in the final output struct
        contrib_summary_df,
        commit_activity_df,
        lang_df, # Add language DF
        overall_stats,
        issue_close_times_data,
        fetched_data.fetch_results # Pass fetch results through
    )

    @info "Data processing complete."
    return processed_data
end
