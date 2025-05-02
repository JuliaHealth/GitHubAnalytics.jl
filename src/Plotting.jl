# src/plotting.jl
using CairoMakie
using DataFrames
using Dates
using Logging
using Statistics
# Note: Types like RepoMetrics, ProcessedData, AnalyticsConfig are available
# because this file is included into the GitHubAnalytics module scope.

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
              xticklabelalign = xticklabelrotation == 0.0 ? (:center, :top) : (:right, :center)
              )
    if xticklabelrotation != 0.0
         fig.layout.padding = (20, 20, max(80, 20 + 10*abs(sind(xticklabelrotation*180/pi))), 20) # Adjust bottom padding based on rotation heuristically
    end
    return fig, ax
end

"""
    _save_plot(fig::Figure, filename_base::String, output_dir::String, logger::AbstractLogger)

Internal helper to save a Makie figure to the specified output directory.
"""
function _save_plot(fig::Figure, filename_base::String, output_dir::String, logger::AbstractLogger)
     filename = filename_base * (endswith(filename_base, ".png") ? "" : ".png")
     filepath = joinpath(output_dir, filename)
     try
          save(filepath, fig, px_per_unit = 2)
          @info "Plot saved successfully: $filepath"
     catch e
          @error "Failed to save plot" path=filepath exception=(e, catch_backtrace())
     end
end


# --- Individual Plotting Functions ---

function _plot_repo_stars(repo_metrics::Vector{RepoMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
    isempty(repo_metrics) && return
    sorted_metrics = sort(repo_metrics, by=m -> m.stars, rev=true)
    display_count = min(config.max_repos_in_plots, length(sorted_metrics))
    plot_metrics = sorted_metrics[1:display_count]
    repo_names = [split(m.name, '/')[end] for m in plot_metrics]
    stars = [m.stars for m in plot_metrics]
    fig, ax = _setup_figure_axis("Top $(display_count) Repositories by Stars", ylabel = "Total Stars", xticklabelrotation = π/4)
    barplot!(ax, 1:display_count, stars, color = :gold)
    ax.xticks = (1:display_count, repo_names); autolimits!(ax)
    _save_plot(fig, "top_repos_by_stars", config.output_dir, logger)
end

function _plot_monthly_commits(repo_metrics::Vector{RepoMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
     isempty(repo_metrics) && return
     active_metrics = filter(m -> m.monthly_commits_last30d > 0, repo_metrics)
     if isempty(active_metrics); @info "No recent commit activity found. Skipping monthly commit plot."; return; end
     sorted_metrics = sort(active_metrics, by=m -> m.monthly_commits_last30d, rev=true)
     display_count = min(config.max_repos_in_plots, length(sorted_metrics))
     plot_metrics = sorted_metrics[1:display_count]
     repo_names = [split(m.name, '/')[end] for m in plot_metrics]
     commits = [m.monthly_commits_last30d for m in plot_metrics]
     fig, ax = _setup_figure_axis("Top $(display_count) Repositories by Commits (Last 30 Days)", ylabel = "Commits", xticklabelrotation = π/4)
     barplot!(ax, 1:display_count, commits, color = :forestgreen)
     ax.xticks = (1:display_count, repo_names); autolimits!(ax)
     _save_plot(fig, "top_repos_by_monthly_commits", config.output_dir, logger)
end

function _plot_issue_status_stacked(repo_metrics::Vector{RepoMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
     isempty(repo_metrics) && return
     repos_with_issues = filter(m -> m.total_issues > 0, repo_metrics)
     if isempty(repos_with_issues); @info "No issues found. Skipping issue status plot."; return; end
     sorted_metrics = sort(repos_with_issues, by=m -> m.total_issues, rev=true)
     display_count = min(config.max_repos_in_plots, length(sorted_metrics))
     plot_metrics = sorted_metrics[1:display_count]
     repo_names = [split(m.name, '/')[end] for m in plot_metrics]
     open_issues = [m.open_issues for m in plot_metrics]
     closed_issues = [m.closed_issues for m in plot_metrics]
     x = 1:display_count
     fig, ax = _setup_figure_axis("Issue Status for Top $(display_count) Repositories (by Total Issues)", ylabel = "Number of Issues", xticklabelrotation = π/4)
     data_matrix = permutedims(hcat(closed_issues, open_issues))
     barplot!(ax, x, data_matrix, stack=1:2, color=[:royalblue, :indianred], label=["Closed Issues", "Open Issues"])
     ax.xticks = (x, repo_names); autolimits!(ax)
     axislegend(ax, position = :rt)
     _save_plot(fig, "issue_status_top_repos", config.output_dir, logger)
end

function _plot_overall_commit_activity(commit_activity::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
      if isempty(commit_activity) || nrow(commit_activity) == 0; @info "No overall commit activity data. Skipping commit plot."; return; end
      if !("date" in names(commit_activity)) || !("commit_count" in names(commit_activity)); @error "Commit DF missing columns. Skipping plot."; return; end
      dates = commit_activity.date; counts = commit_activity.commit_count
      # Handle potential empty dates/counts if filtering happened
      if isempty(dates); @info "No valid dates found in commit activity. Skipping commit plot."; return; end
      start_date = minimum(dates); end_date = maximum(dates)
      date_range_str = "$(Dates.format(start_date, "yyyy-mm-dd")) to $(Dates.format(end_date, "yyyy-mm-dd"))"
      fig, ax = _setup_figure_axis("Organization-Wide Commit Activity ($date_range_str)", xlabel = "Date", ylabel = "Total Commits per Day", xticklabelrotation = π/4, size=(900, 500))
      lines!(ax, dates, counts, color = :darkorange, linewidth = 2)
      if length(dates) > 30 && typeof(ax.xticks) != Makie.Automatic # Check if ticks are already set
          try # Setting ticks/format can fail sometimes depending on backend/data
             ax.xticks = Makie.WilkinsonTicks(7; k_min=5, k_max=10) # Better tick algorithm
             ax.xtickformat = dates -> Dates.format.(Date.(round.(Int64, dates)), "yy-mm-dd") # Shorter format
          catch e
              @warn "Could not set custom date ticks/format" exception=e
          end
      end
      autolimits!(ax)
      _save_plot(fig, "overall_commit_activity", config.output_dir, logger)
end

function _plot_top_contributors(contributor_summary::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
      if isempty(contributor_summary) || nrow(contributor_summary) == 0; @info "No contributor summary data. Skipping contributors plot."; return; end
      if !("contributor_login" in names(contributor_summary)) || !("total_commits" in names(contributor_summary)); @error "Contributor DF missing columns. Skipping plot."; return; end
      display_count = min(config.max_repos_in_plots, nrow(contributor_summary))
      plot_contribs = contributor_summary[1:display_count, :]
      contributors = plot_contribs.contributor_login; commits = plot_contribs.total_commits
      fig, ax = _setup_figure_axis("Top $(display_count) Contributors by Total Commits", ylabel = "Total Commits", xticklabelrotation = π/4)
      barplot!(ax, 1:display_count, commits, color = :mediumpurple)
      ax.xticks = (1:display_count, contributors); autolimits!(ax)
      _save_plot(fig, "top_contributors", config.output_dir, logger)
end

function _plot_overall_issue_distribution_pie(repo_metrics::Vector{RepoMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
     isempty(repo_metrics) && return
     total_open = sum(m.open_issues for m in repo_metrics; init=0)
     total_closed = sum(m.closed_issues for m in repo_metrics; init=0)
     total_issues = total_open + total_closed
     if total_issues == 0; @info "No issues found. Skipping issue distribution pie chart."; return; end
     labels = ["Open Issues", "Closed Issues"]; pie_values = [total_open, total_closed]; colors = [:indianred, :royalblue]
     fig = Figure(size = (600, 500)); ga = fig[1, 1] = GridLayout()
     ax = Axis(ga[1, 1], aspect = DataAspect()); pie!(ax, pie_values, color = colors, strokecolor = :white, strokewidth = 2)
     hidedecorations!(ax); hidespines!(ax)
     Label(ga[0, 1], "Overall Issue Distribution ($total_issues Total)", fontsize=20, tellwidth=false)
     elements = [PolyElement(polycolor = c) for c in colors]; legend_labels = ["$(labels[i]): $(pie_values[i])" for i in 1:length(labels)]
     Legend(ga[1, 2], elements, legend_labels, "Status", valign = :center, halign = :left)
     colgap!(ga, 10); rowgap!(ga, 5)
     _save_plot(fig, "overall_issue_distribution_pie", config.output_dir, logger)
end

function _plot_pr_summary(pr_metrics::Vector{PullRequestMetrics}, config::AnalyticsConfig, logger::AbstractLogger)
      if isempty(pr_metrics); @info "No PR metrics available. Skipping PR summary plot."; return; end
      total_open = sum(p.open_pr_count for p in pr_metrics; init=0); total_closed = sum(p.closed_pr_count for p in pr_metrics; init=0); total_merged = sum(p.merged_pr_count for p in pr_metrics; init=0)
      total_pr = total_open + total_closed + total_merged
      valid_merge_times = [p.avg_merge_time_days for p in pr_metrics if !isnothing(p.avg_merge_time_days)]
      overall_avg_merge_time_str = !isempty(valid_merge_times) ? "$(round(mean(valid_merge_times), digits=1)) days" : "N/A"
      fig = Figure(size = (800, 450)); ga = fig[1, 1] = GridLayout()
      summary_text = """
      **Pull Request Overview**

      Total PRs (Open + Closed + Merged): $total_pr
        - Open: $total_open
        - Merged: $total_merged
        - Closed (Not Merged): $total_closed

      Average Merge Time (across repos with data):
        - $overall_avg_merge_time_str
      """
      box = Box(ga[1, 1], color = (:gray, 0.05), strokecolor = :lightgray, strokewidth=1)
      Label(ga[1, 1], summary_text, justification=:left, valign=:top, halign=:left, padding=(15,15,15,15), tellheight=false)
      labels = ["Open", "Merged", "Closed"]; pr_pie_values = [total_open, total_merged, total_closed]; colors = [:darkorange, :forestgreen, :firebrick]
      if total_pr > 0
          ax_pie = Axis(ga[1, 2], aspect = DataAspect()); pie!(ax_pie, pr_pie_values, color=colors, strokecolor=:white, strokewidth=2)
          hidedecorations!(ax_pie); hidespines!(ax_pie)
          Label(ga[0, 2], "PR Status Distribution", fontsize=16, tellwidth=false, halign=:center)
          elements = [PolyElement(polycolor = c) for c in colors]; legend_labels = ["$(labels[i]): $(pr_pie_values[i])" for i in 1:length(labels)]
          Legend(ga[2, 2], elements, legend_labels, valign=:top, halign = :center, orientation=:horizontal)
      else Label(ga[1, 2], "No Pull Request data found.", halign=:center, valign=:center) end
      colgap!(ga, 20); rowgap!(ga, 5)
      _save_plot(fig, "pull_request_summary", config.output_dir, logger)
end

function _plot_language_distribution_pie(lang_df::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    if isempty(lang_df) || nrow(lang_df) == 0; @info "No language data. Skipping language pie chart."; return; end
    max_langs_in_pie = 10
    sorted_langs = sort(lang_df, :count, rev=true)
    pie_labels = String[]; pie_values = Int[]; pie_colors = Color[]

    # Handle case where 'language' column might contain missing values if constructed improperly
    if Missing <: eltype(sorted_langs.language)
        @warn "Language DataFrame contains missing values, attempting to filter."
        sorted_langs = filter(:language => !ismissing, sorted_langs)
        if isempty(sorted_langs); @info "No non-missing language data. Skipping language pie."; return; end
    end

    if nrow(sorted_langs) > max_langs_in_pie
        top_n = sorted_langs[1:max_langs_in_pie, :]
        other_count = sum(sorted_langs[(max_langs_in_pie + 1):end, :count])
        pie_labels = [top_n.language..., "Other"]
        pie_values = [top_n.count..., other_count]
    else
        pie_labels = sorted_langs.language
        pie_values = sorted_langs.count
    end

    valid_indices = findall(pie_values .> 0)
    if isempty(valid_indices); @info "All language counts zero. Skipping language pie."; return; end
    pie_labels = pie_labels[valid_indices]; pie_values = pie_values[valid_indices]
    pie_colors = Makie.wong_colors(length(pie_labels)) # Generate colors based on final length

    fig = Figure(size = (700, 550)); ga = fig[1, 1] = GridLayout()
    ax = Axis(ga[1, 1], aspect = DataAspect()); pie!(ax, pie_values, color = pie_colors, strokecolor = :white, strokewidth = 2)
    hidedecorations!(ax); hidespines!(ax)
    Label(ga[0, 1], "Primary Language Distribution", fontsize=20, tellwidth=false)
    elements = [PolyElement(polycolor = pie_colors[i]) for i in 1:length(pie_labels)]
    legend_labels = ["$(pie_labels[i]): $(pie_values[i])" for i in 1:length(pie_labels)]
    Legend(ga[1, 2], elements, legend_labels, "Language", valign = :center, halign = :left)
    colgap!(ga, 10); rowgap!(ga, 5)
    _save_plot(fig, "language_distribution_pie", config.output_dir, logger)
end


# --- Main Plotting Function ---
"""
    generate_plots(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger)

Generates all configured plots based on the processed data.
"""
function generate_plots(processed_data::ProcessedData, config::AnalyticsConfig, logger::AbstractLogger)
    @info "Generating visualizations..."
    # Check if repo_metrics exists and is not empty before proceeding
    if !isdefined(processed_data, :repo_metrics) || isempty(processed_data.repo_metrics)
        @warn "No repository metrics found in processed data. Skipping plot generation."
        return
    end

    set_theme!(theme_light())

    # Extract data (handle potential absence of fields gracefully)
    repo_metrics_list = collect(values(processed_data.repo_metrics))
    pr_metrics_list = isdefined(processed_data, :pull_request_metrics) ? collect(values(processed_data.pull_request_metrics)) : PullRequestMetrics[]
    contrib_summary_df = isdefined(processed_data, :contributor_summary) ? processed_data.contributor_summary : DataFrame()
    overall_commit_activity_df = isdefined(processed_data, :overall_commit_activity) ? processed_data.overall_commit_activity : DataFrame()
    language_df = isdefined(processed_data, :language_distribution) ? processed_data.language_distribution : DataFrame()

    # Call individual plot functions safely
    try _plot_repo_stars(repo_metrics_list, config, logger) catch e @error "Failed: _plot_repo_stars" exception=(e, catch_backtrace()) end
    try _plot_monthly_commits(repo_metrics_list, config, logger) catch e @error "Failed: _plot_monthly_commits" exception=(e, catch_backtrace()) end
    try _plot_issue_status_stacked(repo_metrics_list, config, logger) catch e @error "Failed: _plot_issue_status_stacked" exception=(e, catch_backtrace()) end
    try _plot_overall_commit_activity(overall_commit_activity_df, config, logger) catch e @error "Failed: _plot_overall_commit_activity" exception=(e, catch_backtrace()) end
    try _plot_top_contributors(contrib_summary_df, config, logger) catch e @error "Failed: _plot_top_contributors" exception=(e, catch_backtrace()) end
    try _plot_overall_issue_distribution_pie(repo_metrics_list, config, logger) catch e @error "Failed: _plot_overall_issue_distribution_pie" exception=(e, catch_backtrace()) end
    try _plot_pr_summary(pr_metrics_list, config, logger) catch e @error "Failed: _plot_pr_summary" exception=(e, catch_backtrace()) end
    try _plot_language_distribution_pie(language_df, config, logger) catch e @error "Failed: _plot_language_distribution_pie" exception=(e, catch_backtrace()) end

    @info "Visualizations generation attempted. Check logs for success/failure of individual plots."
    set_theme!() # Reset theme
end