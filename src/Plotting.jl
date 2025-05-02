module Plotting

# src/plotting.jl
using CairoMakie
using DataFrames
using Dates
using Logging
using Statistics
using .Structs # Use structs from parent module scope
using .Processing # Need ProcessedData definition

export generate_plots

# --- Plotting Helper Functions ---

"""
    _setup_figure_axis(title; xlabel="", ylabel="", size=(800, 600), xticklabelrotation=0.0) -> Figure, Axis

Internal helper to create a standard Figure and Axis configuration.
"""
function _setup_figure_axis(title; xlabel="", ylabel="", size=(800, 600), xticklabelrotation=0.0)
    fig = Figure(size = size)
    ax = Axis(fig[1, 1],
              title = title,
              xlabel = xlabel,
              ylabel = ylabel,
              xticklabelrotation = xticklabelrotation,
              xticklabelalign = xticklabelrotation == 0.0 ? (:center, :top) : (:right, :center) # Adjust alignment based on rotation
              )
    # Add padding if labels are rotated significantly
    if xticklabelrotation != 0.0
         # Increase bottom padding: (Left, Right, Bottom, Top)
         # Adjust padding as needed based on label length and rotation
         fig.layout.padding = (20, 20, 80, 20)
    end
    return fig, ax
end

"""
    _save_plot(fig::Figure, filename_base::String, output_dir::String, logger::AbstractLogger)

Internal helper to save a Makie figure to the specified output directory.
Uses consistent naming and logs success or failure.
"""
function _save_plot(fig::Figure, filename_base::String, output_dir::String, logger::AbstractLogger)
     # Ensure the filename ends with .png
     filename = filename_base * (endswith(filename_base, ".png") ? "" : ".png")
     filepath = joinpath(output_dir, filename)
     try
          # px_per_unit increases resolution/smoothness
          save(filepath, fig, px_per_unit = 2)
          @info "Plot saved successfully: $filepath"
     catch e
          @error "Failed to save plot" path=filepath exception=(e, catch_backtrace())
     end
end


# --- Individual Plotting Functions ---

"""
Plots the top N repositories based on star count.
"""
function _plot_repo_stars(repo_metrics::Vector{RepoMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
    isempty(repo_metrics) && return

    # Sort by stars
    sorted_metrics = sort(repo_metrics, by=m -> m.stars, rev=true)
    display_count = min(config.max_repos_in_plots, length(sorted_metrics))
    plot_metrics = sorted_metrics[1:display_count]

    # Prepare data for plot
    # Use short names if possible, fallback to full name if needed
    # Assuming RepoMetrics has a way to get short name, otherwise extract from full name
    # repo_names = [m.repo_name_short for m in plot_metrics] # Ideal if short name available
    repo_names = [split(m.name, '/')[end] for m in plot_metrics] # Extract short name
    stars = [m.stars for m in plot_metrics]

    fig, ax = _setup_figure_axis("Top $(display_count) Repositories by Stars",
                                 ylabel = "Total Stars",
                                 xticklabelrotation = π/4) # Rotate labels

    barplot!(ax, 1:display_count, stars, color = :gold) # Changed color

    ax.xticks = (1:display_count, repo_names)
    autolimits!(ax) # Recalculate limits

    _save_plot(fig, "top_repos_by_stars", config.output_dir, logger)
end

"""
Plots the top N repositories based on commit activity in the last 30 days.
"""
function _plot_monthly_commits(repo_metrics::Vector{RepoMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
    isempty(repo_metrics) && return

    # Filter for repos with recent commits and sort
    active_metrics = filter(m -> m.monthly_commits_last30d > 0, repo_metrics)
    if isempty(active_metrics)
        @info "No recent commit activity (last 30d) found in any analyzed repository. Skipping monthly commit plot."
        return
    end

    sorted_metrics = sort(active_metrics, by=m -> m.monthly_commits_last30d, rev=true)
    display_count = min(config.max_repos_in_plots, length(sorted_metrics))
    plot_metrics = sorted_metrics[1:display_count]

    # Prepare data
    # repo_names = [m.repo_name_short for m in plot_metrics] # Ideal
    repo_names = [split(m.name, '/')[end] for m in plot_metrics] # Extract short name
    commits = [m.monthly_commits_last30d for m in plot_metrics]

    fig, ax = _setup_figure_axis("Top $(display_count) Repositories by Commits (Last 30 Days)",
                                 ylabel = "Commits",
                                 xticklabelrotation = π/4)

    barplot!(ax, 1:display_count, commits, color = :forestgreen) # Changed color

    ax.xticks = (1:display_count, repo_names)
    autolimits!(ax)

    _save_plot(fig, "top_repos_by_monthly_commits", config.output_dir, logger)
end

"""
Plots the issue status (open vs closed) for the top N repositories, sorted by open issues.
Uses stacked bars as suggested in the review.
"""
function _plot_issue_status_stacked(repo_metrics::Vector{RepoMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
     isempty(repo_metrics) && return

     # Sort by total issues descending to show most active repos first
     # Alternatively sort by open issues: by=m -> m.open_issues
     repos_with_issues = filter(m -> m.total_issues > 0, repo_metrics)
     if isempty(repos_with_issues)
         @info "No issues found in any analyzed repository. Skipping issue status plot."
         return
     end

     sorted_metrics = sort(repos_with_issues, by=m -> m.total_issues, rev=true)
     display_count = min(config.max_repos_in_plots, length(sorted_metrics))
     plot_metrics = sorted_metrics[1:display_count]

     # Prepare data
     # repo_names = [m.repo_name_short for m in plot_metrics] # Ideal
     repo_names = [split(m.name, '/')[end] for m in plot_metrics] # Extract short name
     open_issues = [m.open_issues for m in plot_metrics]
     closed_issues = [m.closed_issues for m in plot_metrics]
     x = 1:display_count

     fig, ax = _setup_figure_axis("Issue Status for Top $(display_count) Repositories (by Total Issues)",
                                  ylabel = "Number of Issues",
                                  xticklabelrotation = π/4)

     # Stacked bar plot: plot closed first, then open on top
     # Need to provide the matrix where each column is a category (repo), rows are stacks
     data_matrix = permutedims(hcat(closed_issues, open_issues)) # Shape: 2 x display_count

     barplot!(ax, x, data_matrix,
              stack=1:2, # Stack group identifier (use 1 for all if only one stack group)
              color=[:royalblue, :indianred], # Color for each stack row (closed, open)
              label=["Closed Issues", "Open Issues"] # Labels for legend
              )

     ax.xticks = (x, repo_names)
     autolimits!(ax) # Adjust limits for stacked bars

     # Add legend
     axislegend(ax, position = :rt) # Or :ct, :lt, etc.

     _save_plot(fig, "issue_status_top_repos", config.output_dir, logger)
end

"""
Plots the overall commit activity aggregated daily over the fetched period.
"""
function _plot_overall_commit_activity(commit_activity::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    if isempty(commit_activity) || nrow(commit_activity) == 0
        @info "No overall commit activity data available. Skipping commit activity plot."
        return
    end

    # Ensure DataFrame has correct columns: 'date' (Date), 'commit_count' (Int)
    if !("date" in names(commit_activity)) || !("commit_count" in names(commit_activity))
        @error "Overall commit activity DataFrame is missing required columns ('date', 'commit_count'). Skipping plot."
        return
    end

    dates = commit_activity.date
    counts = commit_activity.commit_count

    # Determine date range for better axis limits
    start_date = minimum(dates)
    end_date = maximum(dates)
    date_range_str = "$(Dates.format(start_date, "yyyy-mm-dd")) to $(Dates.format(end_date, "yyyy-mm-dd"))"


    fig, ax = _setup_figure_axis("Organization-Wide Commit Activity ($date_range_str)",
                                xlabel = "Date", ylabel = "Total Commits per Day",
                                xticklabelrotation = π/4, size=(900, 500))

    # Use lines and optional scatter points
    lines!(ax, dates, counts, color = :darkorange, linewidth = 2)
    # scatter!(ax, dates, counts, color = :red, markersize=4) # Optional: add points

    # Improve date tick formatting if many dates
    if length(dates) > 30 # Heuristic: if more than a month of data
         ax.xticks = Makie.LinearTicks(7) # Aim for approx 7 ticks
         ax.xtickformat = dates -> Dates.format.(Date.(round.(Int64, dates)), "yyyy-mm-dd")
    end

    autolimits!(ax)

    _save_plot(fig, "overall_commit_activity", config.output_dir, logger)
end

"""
Plots the top N contributors based on total commit count across all analyzed repositories.
"""
function _plot_top_contributors(contributor_summary::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    if isempty(contributor_summary) || nrow(contributor_summary) == 0
        @info "No contributor summary data available. Skipping top contributors plot."
        return
    end

     # Ensure DataFrame has correct columns: 'contributor_login' (String), 'total_commits' (Int)
     if !("contributor_login" in names(contributor_summary)) || !("total_commits" in names(contributor_summary))
         @error "Contributor summary DataFrame is missing required columns ('contributor_login', 'total_commits'). Skipping plot."
         return
     end

     # Data should already be sorted descending by process_data
     display_count = min(config.max_repos_in_plots, nrow(contributor_summary)) # Use config param here too
     plot_contribs = contributor_summary[1:display_count, :]

     contributors = plot_contribs.contributor_login
     commits = plot_contribs.total_commits

     fig, ax = _setup_figure_axis("Top $(display_count) Contributors by Total Commits",
                                  ylabel = "Total Commits",
                                  xticklabelrotation = π/4)

     barplot!(ax, 1:display_count, commits, color = :mediumpurple) # Changed color

     ax.xticks = (1:display_count, contributors)
     autolimits!(ax)

     _save_plot(fig, "top_contributors", config.output_dir, logger)
end

"""
Plots the overall distribution of open vs closed issues using a pie chart.
"""
function _plot_overall_issue_distribution_pie(repo_metrics::Vector{RepoMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
    isempty(repo_metrics) && return

    total_open = sum(m.open_issues for m in repo_metrics; init=0)
    total_closed = sum(m.closed_issues for m in repo_metrics; init=0)
    total_issues = total_open + total_closed

    if total_issues == 0
        @info "No issues found across repositories. Skipping overall issue distribution pie chart."
        return
    end

    labels = ["Open Issues", "Closed Issues"]
    pie_values = [total_open, total_closed]
    colors = [:indianred, :royalblue]

    fig = Figure(size = (600, 500)) # Adjusted size
    # Use GridLayout for better control over title and legend placement
    ga = fig[1, 1] = GridLayout()

    ax = Axis(ga[1, 1], aspect = DataAspect()) # Pie chart axis

    pie!(ax, pie_values,
         color = colors,
         strokecolor = :white,
         strokewidth = 2,
         # Add labels to slices if needed and space allows
         # label = ["$v" for v in pie_values] # Simple value labels
        )

    hidedecorations!(ax) # Hide axes lines/ticks for pie chart
    hidespines!(ax)      # Hide frame spines

    # Add Title above the pie
    Label(ga[0, 1], "Overall Issue Distribution ($total_issues Total)", fontsize=20, tellwidth=false)

    # Add Legend to the side
    elements = [PolyElement(polycolor = c) for c in colors]
    # Include counts in legend labels
    legend_labels = ["$(labels[i]): $(pie_values[i])" for i in 1:length(labels)]
    Legend(ga[1, 2], elements, legend_labels, "Status", valign = :center, halign = :left)

    colgap!(ga, 10) # Add gap between pie and legend
    rowgap!(ga, 5)  # Add gap between title and pie

    _save_plot(fig, "overall_issue_distribution_pie", config.output_dir, logger)
end

"""
Generates a summary plot/panel for Pull Request metrics.
Includes a text summary and a pie chart of PR statuses.
"""
function _plot_pr_summary(pr_metrics::Vector{PullRequestMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
     if isempty(pr_metrics)
         @info "No Pull Request metrics available. Skipping PR summary plot."
         return
     end

     # Aggregate PR stats
     total_open = sum(p.open_pr_count for p in pr_metrics; init=0)
     total_closed = sum(p.closed_pr_count for p in pr_metrics; init=0)
     total_merged = sum(p.merged_pr_count for p in pr_metrics; init=0)
     total_pr = total_open + total_closed + total_merged

     # Calculate overall average merge time (simple average of repo averages)
     valid_merge_times = [p.avg_merge_time_days for p in pr_metrics if !isnothing(p.avg_merge_time_days)]
     overall_avg_merge_time_str = if !isempty(valid_merge_times)
         avg_val = round(mean(valid_merge_times), digits=1)
         "$avg_val days"
     else
         "N/A"
     end

     fig = Figure(size = (800, 450)) # Adjusted size
     ga = fig[1, 1] = GridLayout()

     # Text Summary Box (Left Side)
     summary_text = """
     **Pull Request Overview**

     Total PRs (Open + Closed + Merged): $total_pr
       - Open: $total_open
       - Merged: $total_merged
       - Closed (Not Merged): $total_closed

     Average Merge Time (across repos with data):
       - $overall_avg_merge_time_str
     """
     # Use a Label within a Box for better visual separation
     box = Box(ga[1, 1], color = (:gray, 0.05), strokecolor = :lightgray, strokewidth=1)
     Label(ga[1, 1], summary_text, justification=:left, valign=:top, halign=:left, padding=(15,15,15,15), tellheight=false) # Use Label for multiline text


     # Pie chart of PR status (Right Side)
     labels = ["Open", "Merged", "Closed"]
     pr_pie_values = [total_open, total_merged, total_closed]
     colors = [:darkorange, :forestgreen, :firebrick] # Different colors for PRs

     if total_pr > 0 # Only plot if there are PRs
          ax_pie = Axis(ga[1, 2], aspect = DataAspect())
          pie!(ax_pie, pr_pie_values, color=colors, strokecolor=:white, strokewidth=2)
          hidedecorations!(ax_pie)
          hidespines!(ax_pie)

          # Add Title for the pie chart section
          Label(ga[0, 2], "PR Status Distribution", fontsize=16, tellwidth=false, halign=:center)

          # Add Legend below the pie or to the side
          elements = [PolyElement(polycolor = c) for c in colors]
          legend_labels = ["$(labels[i]): $(pr_pie_values[i])" for i in 1:length(labels)]
          Legend(ga[2, 2], elements, legend_labels, valign=:top, halign = :center, orientation=:horizontal) # Horizontal legend below

     else
          Label(ga[1, 2], "No Pull Request data found.", halign=:center, valign=:center)
     end

     # Adjust layout spacing
     colgap!(ga, 20)
     rowgap!(ga, 5) # Gap between title and pie, and pie and legend

     # Overall Title for the Figure
     # Label(ga[0, 1:2], "Pull Request Analysis Summary", fontsize=20, tellwidth=false, halign=:center)

     _save_plot(fig, "pull_request_summary", config.output_dir, logger)
end


# --- Main Plotting Function ---

"""
    generate_plots(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger)

Generates all configured plots based on the processed data.
"""
function generate_plots(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger)
    @info "Generating visualizations..."
    set_theme!(theme_light()) # Use a default theme

    # Extract data for convenience (convert dict values to vectors where needed)
    repo_metrics_list = collect(values(processed_data.repo_metrics))
    pr_metrics_list = collect(values(processed_data.pull_request_metrics))
    contributor_summary_df = processed_data.contributor_summary
    overall_commit_activity_df = processed_data.overall_commit_activity

    # Call individual plot functions
    _plot_repo_stars(repo_metrics_list, config, logger)
    _plot_monthly_commits(repo_metrics_list, config, logger)
    _plot_issue_status_stacked(repo_metrics_list, config, logger) # Use stacked version
    _plot_overall_commit_activity(overall_commit_activity_df, config, logger)
    _plot_top_contributors(contributor_summary_df, config, logger)
    _plot_overall_issue_distribution_pie(repo_metrics_list, config, logger)
    _plot_pr_summary(pr_metrics_list, config, logger)
    # Add calls to other plot functions here if implemented

    @info "Visualizations generated in $(config.output_dir)"
    set_theme!() # Reset theme to default
end
end#module Plotting