# src/reporting.jl
using DataFrames
using CSV
using Dates
using Logging
using Statistics
using Markdown


"""
    generate_csv_reports(processed_data::ProcessedData, output_dir::String, logger::AbstractLogger)

Generates CSV files containing the processed repository metrics and contributor summary.
"""
function generate_csv_reports(processed_data::ProcessedData, output_dir::String, logger::AbstractLogger)
    @info "Generating CSV reports..."
    timestamp = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
    repo_metrics_dict = processed_data.repo_metrics
    pr_metrics_dict = processed_data.pull_request_metrics
    # ... code to build repo_data_for_df ...
    if isempty(repo_metrics_dict)
        @warn "No repository metrics available to generate CSV report."
        return # Return early if no data
    end
    repo_data_for_df = []
    sorted_repo_names = sort(collect(keys(repo_metrics_dict)))
    for repo_name in sorted_repo_names
        rm = repo_metrics_dict[repo_name]
        pr_m = get(pr_metrics_dict, repo_name, nothing)
        push!(repo_data_for_df, (; # Use NamedTuple literal syntax
            name = rm.name, stars = rm.stars, forks = rm.forks,
            language = something(rm.primary_language, missing),
            created_at = Dates.format(rm.created_at, "yyyy-mm-dd"),
            age_days = rm.age_days,
            last_api_update = Dates.format(rm.last_api_update, "yyyy-mm-dd HH:MM"),
            open_issues = rm.open_issues, closed_issues = rm.closed_issues, total_issues = rm.total_issues,
            issue_resolution_rate = something(rm.issue_resolution_rate, missing),
            monthly_commits_last30d = rm.monthly_commits_last30d,
            total_commits_fetched_period = rm.total_commits_fetched_period,
            open_pr = isnothing(pr_m) ? missing : pr_m.open_pr_count,
            closed_pr = isnothing(pr_m) ? missing : pr_m.closed_pr_count,
            merged_pr = isnothing(pr_m) ? missing : pr_m.merged_pr_count,
            total_pr = isnothing(pr_m) ? missing : pr_m.total_pr_count,
            avg_merge_time_days = isnothing(pr_m) ? missing : something(pr_m.avg_merge_time_days, missing)
        ))
    end
    df_repos = DataFrame(repo_data_for_df)
    sort!(df_repos, :stars, rev=true)
    csv_path = joinpath(output_dir, "repository_metrics_$(timestamp).csv")
    try CSV.write(csv_path, df_repos)
        @info "Repository metrics saved to $csv_path"
    catch e @error "Failed to write repository metrics CSV" path=csv_path exception=(e, catch_backtrace()) end
    # ... save contributor_summary_df ...
    contrib_summary_df = processed_data.contributor_summary
    if !isempty(contrib_summary_df)
        csv_path_contrib = joinpath(output_dir, "contributor_summary_$(timestamp).csv")
        try CSV.write(csv_path_contrib, contrib_summary_df)
            @info "Contributor summary saved to $csv_path_contrib"
        catch e @error "Failed to write contributor summary CSV" path=csv_path_contrib exception=(e, catch_backtrace()) end
    else @info "No contributor summary data available for CSV report." end
     # ... save overall_commit_activity ...
     overall_commit_df = processed_data.overall_commit_activity
     if !isempty(overall_commit_df)
         csv_path_commits = joinpath(output_dir, "overall_commit_activity_$(timestamp).csv")
         try CSV.write(csv_path_commits, overall_commit_df)
             @info "Overall commit activity saved to $csv_path_commits"
         catch e @error "Failed to write overall commit activity CSV" path=csv_path_commits exception=(e, catch_backtrace()) end
     else @info "No overall commit activity data available for CSV report." end
    # ... save language distribution ...
    lang_df = processed_data.language_distribution
     if !isempty(lang_df)
         csv_path_langs = joinpath(output_dir, "language_distribution_$(timestamp).csv")
         try CSV.write(csv_path_langs, lang_df)
             @info "Language distribution saved to $csv_path_langs"
         catch e @error "Failed to write language distribution CSV" path=csv_path_langs exception=(e, catch_backtrace()) end
     else @info "No language distribution data available for CSV report." end

    @info "CSV report generation finished."
    
    # Add export of issue close times data if available
    issue_close_times_df = isdefined(processed_data, :issue_close_times) ? processed_data.issue_close_times : DataFrame()
    if !isempty(issue_close_times_df)
        csv_path_issue_times = joinpath(output_dir, "issue_close_times_$(timestamp).csv")
        try
            # Add repo display name for easier reading
            if !("repo_display" in names(issue_close_times_df))
                issue_close_times_df.repo_display = [split(r, '/')[end] for r in issue_close_times_df.repo_name]
            end
            CSV.write(csv_path_issue_times, issue_close_times_df)
            @info "Issue close times saved to $csv_path_issue_times"
        catch e
            @error "Failed to write issue close times CSV" path=csv_path_issue_times exception=(e, catch_backtrace())
        end
    else
        @info "No issue close time data available for CSV report."
    end
end



"""
    generate_markdown_summary(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger)

Generates a comprehensive Markdown report summarizing all the analyzed data.
"""
function generate_markdown_summary(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger)
    @info "Generating markdown summary report..."
    
    # Extract data needed for the report
    repo_metrics = collect(values(processed_data.repo_metrics))
    pr_metrics = isdefined(processed_data, :pull_request_metrics) ? collect(values(processed_data.pull_request_metrics)) : PullRequestMetrics[]
    contrib_summary = isdefined(processed_data, :contributor_summary) ? processed_data.contributor_summary : DataFrame()
    language_df = isdefined(processed_data, :language_distribution) ? processed_data.language_distribution : DataFrame()
    issue_close_times = isdefined(processed_data, :issue_close_times) ? processed_data.issue_close_times : DataFrame()
    
    # Get overall stats
    overall_stats = isdefined(processed_data, :overall_stats) ? processed_data.overall_stats : Dict{String, Any}()
    
    # Sort repo metrics by stars (most popular first)
    sort!(repo_metrics, by = r -> r.stars, rev = true)
    
    # Open markdown report file
    report_path = joinpath(config.output_dir, "github_analysis_report.md")
    open(report_path, "w") do f
        # Document Header
        today_date = Dates.format(today(), "yyyy-mm-dd")
        if length(config.targets) == 1
            target_name = config.targets[1]
            header = "# GitHub Analytics Report for $target_name\n\n"
        else
            header = "# GitHub Analytics Report\n\n"
        end
        header *= "Report Generated: $today_date\n\n"
        header *= "This report analyzes GitHub repositories from the following targets: $(join(config.targets, ", "))\n\n"
        write(f, header)
        
        # === Write Executive Summary ===
        write(f, "## Executive Summary\n\n")
        
        # Calculate overall statistics
        total_repos = length(repo_metrics)
        total_stars = sum(r.stars for r in repo_metrics)
        total_forks = sum(r.forks for r in repo_metrics)
        total_open_issues = sum(r.open_issues for r in repo_metrics)
        total_closed_issues = sum(r.closed_issues for r in repo_metrics)
        total_issues = total_open_issues + total_closed_issues
        issue_resolution_rate = total_issues > 0 ? round(total_closed_issues / total_issues * 100, digits=1) : 0.0
        
        # Calculate PR statistics if available
        if !isempty(pr_metrics)
            total_open_prs = sum(pr.open_pr_count for pr in pr_metrics)
            total_merged_prs = sum(pr.merged_pr_count for pr in pr_metrics)
            total_closed_prs = sum(pr.closed_pr_count for pr in pr_metrics)
            total_prs = total_open_prs + total_merged_prs + total_closed_prs
            pr_merge_rate = total_prs > 0 ? round((total_merged_prs / total_prs) * 100, digits=1) : 0.0
            
            # Average merge time calculation
            valid_merge_times = [pr.avg_merge_time_days for pr in pr_metrics if !isnothing(pr.avg_merge_time_days)]
            avg_merge_time = !isempty(valid_merge_times) ? round(mean(valid_merge_times), digits=1) : nothing
        else
            total_prs = 0
            pr_merge_rate = 0.0
            avg_merge_time = nothing
        end
        
        # Write summary statistics
        summary = """
        Total repositories analyzed: $total_repos
        
        **Overall Metrics:**
        - Total Stars: $total_stars
        - Total Forks: $total_forks
        - Total Issues: $total_issues (Open: $total_open_issues, Closed: $total_closed_issues)
        - Issue Resolution Rate: $issue_resolution_rate%
        """
        
        if total_prs > 0
            pr_summary = """
            - Total Pull Requests: $total_prs (Open: $total_open_prs, Merged: $total_merged_prs, Closed: $total_closed_prs)
            - PR Merge Rate: $pr_merge_rate%
            """
            if !isnothing(avg_merge_time)
                pr_summary *= "- Average PR Merge Time: $avg_merge_time days\n"
            end
            summary *= pr_summary
        end
        
        # Add issue close time summary if available
        if !isempty(issue_close_times)
            median_close_time = round(median(issue_close_times.close_time_days), digits=1)
            mean_close_time = round(mean(issue_close_times.close_time_days), digits=1)
            p90_close_time = round(quantile(issue_close_times.close_time_days, 0.90), digits=1)
            
            issue_close_summary = """
            
            **Issue Resolution Statistics:**
            - Median Time to Close: $median_close_time days
            - Mean Time to Close: $mean_close_time days
            - 90% of issues closed within: $p90_close_time days
            - Total closed issues analyzed: $(nrow(issue_close_times))
            """
            
            summary *= issue_close_summary
        end
        
        # Add language summary if available
        if !isempty(language_df) && nrow(language_df) > 0
            top_languages = first(language_df, min(5, nrow(language_df)))
            lang_summary = "\n**Top Languages:**\n"
            for row in eachrow(top_languages)
                lang_summary *= "- $(row.language): $(row.count) repositories\n"
            end
            summary *= lang_summary
        end
        
        write(f, summary)
        
        # === Repository Details ===
        if !isempty(repo_metrics)
            write(f, "\n## Repository Details\n\n")
            
            # Limit to top repositories if there are many
            display_repos = length(repo_metrics) > 20 ? repo_metrics[1:20] : repo_metrics
            
            # Create repository metrics table
            repo_table = "| Repository | Stars | Forks | Open Issues | Closed Issues | Issue Resolution Rate |\n"
            repo_table *= "|------------|-------|-------|------------|---------------|----------------------|\n"
            
            for repo in display_repos
                resolution_rate = repo.total_issues > 0 ? "$(round(Int, repo.closed_issues / repo.total_issues * 100))%" : "N/A"
                repo_table *= "| $(repo.name) | $(repo.stars) | $(repo.forks) | $(repo.open_issues) | $(repo.closed_issues) | $resolution_rate |\n"
            end
            
            if length(repo_metrics) > 20
                repo_table *= "\n*Note: Showing top 20 repositories by stars. $(length(repo_metrics) - 20) more repositories were analyzed.*\n"
            end
            
            write(f, repo_table)
        end
        
        # === Issue Management ===
        if total_issues > 0
            write(f, "\n## Issue Management\n\n")
            
            issue_summary = """
            Total issues across all repositories: $total_issues
            - Open issues: $total_open_issues ($(round(Int, total_open_issues / total_issues * 100))%)
            - Closed issues: $total_closed_issues ($(round(Int, total_closed_issues / total_issues * 100))%)
            
            Overall issue resolution rate: $issue_resolution_rate%
            
            """
            
            # Add the issue close time analysis section
            if !isempty(issue_close_times)
                issue_summary *= "### Issue Close Time Analysis\n\n"
                
                # Calculate statistics
                q1 = round(quantile(issue_close_times.close_time_days, 0.25), digits=1)
                median_val = round(median(issue_close_times.close_time_days), digits=1)
                q3 = round(quantile(issue_close_times.close_time_days, 0.75), digits=1)
                mean_val = round(mean(issue_close_times.close_time_days), digits=1)
                max_val = round(maximum(issue_close_times.close_time_days), digits=1)
                
                issue_summary *= """
                The time to close issues is an important indicator of repository health and maintainer responsiveness.
                
                **Key statistics:**
                - 25% of issues are closed within $q1 days
                - Median close time: $median_val days
                - 75% of issues are closed within $q3 days
                - Mean close time: $mean_val days
                - Maximum close time: $max_val days
                
                """
                
                # Add analysis of repositories with fastest issue resolution
                if nrow(issue_close_times) >= 5
                    repo_median_close_times = combine(groupby(issue_close_times, :repo_name), 
                                                   nrow => :issue_count,
                                                   :close_time_days => median => :median_days)
                    
                    # Filter to repos with meaningful sample size
                    repo_median_close_times = filter(row -> row.issue_count >= 5, repo_median_close_times)
                    
                    if nrow(repo_median_close_times) > 0
                        sort!(repo_median_close_times, :median_days)
                        fastest_repos = first(repo_median_close_times, min(5, nrow(repo_median_close_times)))
                        
                        issue_summary *= "**Repositories with fastest issue resolution (minimum 5 issues):**\n\n"
                        issue_summary *= "| Repository | Median Close Time (days) | Issues Analyzed |\n"
                        issue_summary *= "|------------|--------------------------|----------------|\n"
                        
                        for row in eachrow(fastest_repos)
                            repo_display = split(row.repo_name, '/')[end]
                            issue_summary *= "| $repo_display | $(round(row.median_days, digits=1)) | $(row.issue_count) |\n"
                        end
                        
                        issue_summary *= "\n"
                    end
                end
                
                # Add time trend if possible
                if nrow(issue_close_times) >= 20
                    issue_summary *= "### Issue Resolution Time Trend\n\n"
                    issue_summary *= "The trend of issue resolution times can indicate improving or declining repository maintenance.\n"
                    issue_summary *= "Refer to the generated visualization for a detailed view of this trend.\n\n"
                end
            end
            
            write(f, issue_summary)
        end
        
        # Add footer
        footer = "\n---\n\nGenerated by [GitHubAnalytics.jl](https://github.com/yourusername/GitHubAnalytics.jl) · $(Dates.format(now(), "yyyy-mm-dd HH:MM"))\n"
        write(f, footer)
    end
    
    @info "Markdown report generated successfully at: $report_path"
    return report_path
end