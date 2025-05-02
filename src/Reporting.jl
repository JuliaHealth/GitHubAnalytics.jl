module Reporting
# src/reporting.jl
using DataFrames
using CSV
using Dates
using Logging
using Statistics
using .Structs # Use structs from parent module scope
using .Processing # Need ProcessedData definition (assuming Processing defines it)

export generate_csv_reports, generate_markdown_summary

"""
    generate_csv_reports(processed_data::ProcessedData, output_dir::String, logger::AbstractLogger)

Generates CSV files containing the processed repository metrics and contributor summary.
"""
function generate_csv_reports(processed_data::ProcessedData, output_dir::String, logger::AbstractLogger)
    @info "Generating CSV reports..."
    timestamp = Dates.format(now(), "yyyy-mm-dd_HHMMSS")

    # --- Repository Metrics CSV ---
    repo_metrics_dict = processed_data.repo_metrics
    pr_metrics_dict = processed_data.pull_request_metrics

    if isempty(repo_metrics_dict)
        @warn "No repository metrics available to generate CSV report."
    else
        repo_data_for_df = []
        # Sort keys to ensure consistent order (optional)
        sorted_repo_names = sort(collect(keys(repo_metrics_dict)))

        for repo_name in sorted_repo_names
            rm = repo_metrics_dict[repo_name]
            pr_m = get(pr_metrics_dict, repo_name, nothing) # Get matching PR metric

            push!(repo_data_for_df, (; # Use NamedTuple literal syntax
                name = rm.name,
                stars = rm.stars,
                forks = rm.forks,
                language = something(rm.primary_language, missing), # Use missing for CSV
                created_at = Dates.format(rm.created_at, "yyyy-mm-dd"),
                age_days = rm.age_days,
                last_api_update = Dates.format(rm.last_api_update, "yyyy-mm-dd HH:MM"),
                open_issues = rm.open_issues,
                closed_issues = rm.closed_issues,
                total_issues = rm.total_issues,
                issue_resolution_rate = something(rm.issue_resolution_rate, missing),
                monthly_commits_last30d = rm.monthly_commits_last30d,
                total_commits_fetched_period = rm.total_commits_fetched_period,
                # PR Metrics (handle missing data)
                open_pr = isnothing(pr_m) ? missing : pr_m.open_pr_count,
                closed_pr = isnothing(pr_m) ? missing : pr_m.closed_pr_count,
                merged_pr = isnothing(pr_m) ? missing : pr_m.merged_pr_count,
                total_pr = isnothing(pr_m) ? missing : pr_m.total_pr_count,
                avg_merge_time_days = isnothing(pr_m) ? missing : something(pr_m.avg_merge_time_days, missing)
            ))
        end

        df_repos = DataFrame(repo_data_for_df)
        sort!(df_repos, :stars, rev=true) # Default sort by stars

        csv_path = joinpath(output_dir, "repository_metrics_$(timestamp).csv")
        try
            # Use standard missing representation for CSV
            CSV.write(csv_path, df_repos)
            @info "Repository metrics saved to $csv_path"
        catch e
            @error "Failed to write repository metrics CSV" path=csv_path exception=(e, catch_backtrace())
        end
    end

    # --- Contributor Summary CSV ---
    contrib_summary_df = processed_data.contributor_summary
    if isempty(contrib_summary_df)
        @info "No contributor summary data available to generate CSV report." # Info, as fetch might be disabled
    else
        csv_path_contrib = joinpath(output_dir, "contributor_summary_$(timestamp).csv")
        try
            CSV.write(csv_path_contrib, contrib_summary_df)
            @info "Contributor summary saved to $csv_path_contrib"
        catch e
            @error "Failed to write contributor summary CSV" path=csv_path_contrib exception=(e, catch_backtrace())
        end
    end

     # --- Overall Commit Activity CSV ---
     overall_commit_df = processed_data.overall_commit_activity
     if isempty(overall_commit_df)
         @info "No overall commit activity data available to generate CSV report."
     else
         csv_path_commits = joinpath(output_dir, "overall_commit_activity_$(timestamp).csv")
         try
             CSV.write(csv_path_commits, overall_commit_df)
             @info "Overall commit activity saved to $csv_path_commits"
         catch e
             @error "Failed to write overall commit activity CSV" path=csv_path_commits exception=(e, catch_backtrace())
         end
     end

    @info "CSV report generation finished."
end


"""
    generate_markdown_summary(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger)

Generates a Markdown summary file reporting key metrics and linking to plots/CSVs.
"""
function generate_markdown_summary(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger)
    @info "Generating Markdown summary..."
    timestamp_file = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
    timestamp_report = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    md_path = joinpath(config.output_dir, "summary_$(timestamp_file).md")

    metrics_list = collect(values(processed_data.repo_metrics)) # Convert dict values to vector
    pr_metrics_list = collect(values(processed_data.pull_request_metrics))
    overall_stats = processed_data.overall_stats
    contrib_summary = processed_data.contributor_summary

    # Define relative paths for links (assuming plots/CSVs are in the same dir)
    repo_csv_filename = "repository_metrics_$(timestamp_file).csv"
    contrib_csv_filename = "contributor_summary_$(timestamp_file).csv"
    commit_csv_filename = "overall_commit_activity_$(timestamp_file).csv"
    # Plot filenames need to be known/consistent from plotting step
    # Let's assume standard names for now:
    plot_stars_filename = "top_repos_by_stars.png"
    plot_commits_filename = "top_repos_by_monthly_commits.png"
    plot_issues_filename = "issue_status_top_repos.png"
    plot_overall_commits_filename = "overall_commit_activity.png"
    plot_contributors_filename = "top_contributors.png"
    plot_issue_dist_filename = "overall_issue_distribution_pie.png"
    plot_pr_summary_filename = "pull_request_summary.png"


    try
        open(md_path, "w") do io
            target_names = join(config.targets, ", ")
            println(io, "# GitHub Analytics Summary: `$target_names`") # Use target names from config
            println(io, "_Generated on: $timestamp_report_\n")

            println(io, "## Overall Summary")
            total_repos = length(metrics_list)
            println(io, "- **Repositories Analyzed:** $total_repos")
            if total_repos > 0
                 total_stars = sum(m.stars for m in metrics_list; init=0)
                 total_forks = sum(m.forks for m in metrics_list; init=0)
                 total_open_issues = sum(m.open_issues for m in metrics_list; init=0)
                 total_closed_issues = sum(m.closed_issues for m in metrics_list; init=0)
                 total_issues = total_open_issues + total_closed_issues
                 overall_resolution = total_issues > 0 ? round(total_closed_issues / total_issues * 100, digits=1) : 0.0

                 total_open_pr = sum(p.open_pr_count for p in pr_metrics_list; init=0)
                 total_merged_pr = sum(p.merged_pr_count for p in pr_metrics_list; init=0)
                 total_closed_pr = sum(p.closed_pr_count for p in pr_metrics_list; init=0)

                 all_langs = unique(filter(!isnothing, [m.primary_language for m in metrics_list]))
                 lang_string = isempty(all_langs) ? "N/A" : join(all_langs, ", ")

                 println(io, "- **Total Stars:** $total_stars")
                 println(io, "- **Total Forks:** $total_forks")
                 println(io, "- **Total Issues:** $total_issues (Open: $total_open_issues, Closed: $total_closed_issues)")
                 println(io, "- **Overall Issue Resolution Rate:** $(overall_resolution)%")
                 println(io, "- **Total PRs:** $(total_open_pr + total_merged_pr + total_closed_pr) (Open: $total_open_pr, Merged: $total_merged_pr, Closed (Not Merged): $total_closed_pr)")
                 println(io, "- **Primary Languages:** $lang_string\n")
            else
                 println(io, "_No repository data available for summary._\n")
            end


            println(io, "## Top 5 Repositories by Stars")
            if !isempty(metrics_list)
                sorted_by_stars = sort(metrics_list, by=m -> m.stars, rev=true)
                for (i, m) in enumerate(sorted_by_stars[1:min(5, length(sorted_by_stars))])
                    println(io, "$(i). **$(m.name):** $(m.stars) stars")
                end
            else
                println(io, "_No repository data available._")
            end

            println(io, "\n## Top 5 Repositories by Monthly Commits (Last 30 Days)")
            if !isempty(metrics_list)
                 active_repos = filter(m->m.monthly_commits_last30d > 0, metrics_list)
                 if !isempty(active_repos)
                      sorted_by_commits = sort(active_repos, by=m -> m.monthly_commits_last30d, rev=true)
                      for (i, m) in enumerate(sorted_by_commits[1:min(5, length(sorted_by_commits))])
                          println(io, "$(i). **$(m.name):** $(m.monthly_commits_last30d) commits")
                      end
                 else
                      println(io, "_No recent commit activity detected in analyzed repositories._")
                 end
            else
                 println(io, "_No repository data available._")
            end


            println(io, "\n## Top 5 Repositories by Issue Resolution Rate")
             if !isempty(metrics_list)
                  # Filter for repos with issues to make rate meaningful, handle potential Nothing rate
                  repos_with_issues = filter(m -> m.total_issues > 0 && !isnothing(m.issue_resolution_rate), metrics_list)
                  if !isempty(repos_with_issues)
                       sorted_by_resolution = sort(repos_with_issues, by=m -> m.issue_resolution_rate, rev=true)
                       for (i, m) in enumerate(sorted_by_resolution[1:min(5, length(sorted_by_resolution))])
                           rate = round(m.issue_resolution_rate * 100, digits=1)
                           println(io, "$(i). **$(m.name):** $(rate)% ($(m.closed_issues)/$(m.total_issues))")
                       end
                  else
                       println(io, "_No repositories with valid issue resolution rates found._")
                  end
             else
                  println(io, "_No repository data available._")
             end

            println(io, "\n## Top 5 Contributors by Total Commits")
            if !isempty(contrib_summary)
                # Assumes contrib_summary is already sorted by total_commits desc
                for (i, row) in enumerate(eachrow(contrib_summary[1:min(5, nrow(contrib_summary)), :]))
                    println(io, "$(i). **$(row.contributor_login):** $(row.total_commits) commits")
                end
            else
                println(io, "_No contributor data processed or available._")
            end


            println(io, "\n## Generated Visualizations")
            if config.generate_plots # Only list plots if they were generated
                 println(io, "- [Top Repos by Stars]($plot_stars_filename)")
                 println(io, "- [Top Repos by Monthly Commits]($plot_commits_filename)")
                 println(io, "- [Issue Status for Top Repos]($plot_issues_filename)")
                 println(io, "- [Overall Commit Activity]($plot_overall_commits_filename)")
                 println(io, "- [Top Contributors]($plot_contributors_filename)")
                 println(io, "- [Overall Issue Distribution]($plot_issue_dist_filename)")
                 println(io, "- [Pull Request Summary]($plot_pr_summary_filename)")
                 # Add links to other generated plots if implemented
            else
                 println(io, "_Plot generation was disabled._")
            end

            println(io, "\n## Data Files")
            if config.generate_csv # Only list CSVs if they were generated
                 if !isempty(processed_data.repo_metrics)
                     println(io, "- [Repository Metrics CSV]($repo_csv_filename)")
                 end
                 if !isempty(processed_data.contributor_summary)
                     println(io, "- [Contributor Summary CSV]($contrib_csv_filename)")
                 end
                  if !isempty(processed_data.overall_commit_activity)
                     println(io, "- [Overall Commit Activity CSV]($commit_csv_filename)")
                 end
            else
                 println(io, "_CSV generation was disabled._")
            end

        end # open file
        @info "Markdown summary saved to $md_path"
    catch e
        @error "Failed to write Markdown summary" path=md_path exception=(e, catch_backtrace())
    end
end
end#module Reporting