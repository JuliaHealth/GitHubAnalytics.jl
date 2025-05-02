# src/plotting.jl
using CairoMakie
using DataFrames
using Dates
using Logging
using Statistics
using Colors # Add explicit import for Colors
using ColorTypes # Add explicit import for RGB type
# Note: Types like RepoMetrics, ProcessedData, AnalyticsConfig are available
# because this file is included into the GitHubAnalytics module scope.

# Define aliases to avoid ambiguity
const MakieLabel = CairoMakie.Label
const MakieColor = Colors.Colorant

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
        fig[1, 1] = ax
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
     total_issues = [m.total_issues for m in plot_metrics]
     
     # Calculate percentage for better relative magnitude visualization
     open_pct = [m.open_issues / m.total_issues for m in plot_metrics]
     closed_pct = [m.closed_issues / m.total_issues for m in plot_metrics]
     
     x = 1:display_count
     
     # Create two figures: one with absolute counts and one with percentages
     fig_counts, ax_counts = _setup_figure_axis("Issue Status for Top $(display_count) Repositories", 
                                  ylabel = "Number of Issues", 
                                  xticklabelrotation = π/4)
     
     fig_pct, ax_pct = _setup_figure_axis("Issue Status Distribution (Percentage)", 
                                  ylabel = "Percentage of Issues", 
                                  xticklabelrotation = π/4)
     
     # Absolute count plot
     barplot!(ax_counts, x, closed_issues, color = :royalblue, label = "Closed Issues")
     barplot!(ax_counts, x, open_issues, color = :indianred, label = "Open Issues", 
              stack = closed_issues)
     
     # Add total issue counts as text labels on top of each bar
     for (i, total) in enumerate(total_issues)
         text!(ax_counts, i, total + (total * 0.03), text = "$(total)", 
               align = (:center, :bottom), fontsize = 12)
     end
     
     # Percentage plot
     barplot!(ax_pct, x, closed_pct, color = :royalblue, label = "Closed Issues")
     barplot!(ax_pct, x, open_pct, color = :indianred, label = "Open Issues", 
              stack = closed_pct)
     
     # Add percentage labels
     for (i, (open_p, closed_p)) in enumerate(zip(open_pct, closed_pct))
         # Label for closed percentage at the middle of its section
         text!(ax_pct, i, closed_p/2, text = "$(round(Int, closed_p*100))%", 
               align = (:center, :center), fontsize = 12, color = :white)
         
         # Label for open percentage at the middle of its section (if large enough)
         if open_p > 0.1  # Only add label if segment is large enough
             text!(ax_pct, i, closed_p + open_p/2, text = "$(round(Int, open_p*100))%", 
                  align = (:center, :center), fontsize = 12, color = :white)
         end
     end
     
     # Set axis properties
     ax_counts.xticks = (x, repo_names)
     ax_pct.xticks = (x, repo_names)
     ylims!(ax_pct, (0, 1.0))
     
     # Add legends
     axislegend(ax_counts, position = :rt)
     axislegend(ax_pct, position = :rt)
     
     # Save plots
     _save_plot(fig_counts, "issue_status_top_repos", config.output_dir, logger)
     _save_plot(fig_pct, "issue_status_percentage", config.output_dir, logger)
end

function _plot_overall_commit_activity(commit_activity::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    if isempty(commit_activity) || nrow(commit_activity) == 0
        @info "No overall commit activity data. Skipping commit plot."
        return
    end
    
    # Check required columns
    if !(:date in propertynames(commit_activity)) || !(:commit_count in propertynames(commit_activity))
        @error "Commit DataFrame missing required columns (date, commit_count). Skipping plot."
        return
    end
    
    # Extract and convert data
    @info "Commit activity data shape: $(size(commit_activity)). First row: $(first(commit_activity))"
    
    # Make a copy to avoid modifying the original
    working_df = copy(commit_activity)
    
    # Convert dates to Date type if they're not already
    if !(eltype(working_df.date) <: Date)
        @info "Converting dates to Date type"
        try
            working_df.date = Date.(working_df.date)
        catch e
            @error "Failed to convert dates" exception=e
            return
        end
    end
    
    # Convert counts to Int type if they're not already
    if !(eltype(working_df.commit_count) <: Integer)
        @info "Converting commit counts to Int type"
        try
            working_df.commit_count = Int.(working_df.commit_count)
        catch e
            @error "Failed to convert commit counts" exception=e
            return
        end
    end
    
    # Handle potential empty dates/counts
    if isempty(working_df.date)
        @info "No valid dates found in commit activity. Skipping commit plot."
        return
    end
    
    # Verify we have actual commit data
    total_commits = sum(working_df.commit_count)
    if total_commits == 0
        @info "Total commit count is zero. No activity to display in commit plot."
        return
    else
        @info "Found $total_commits commits across $(nrow(working_df)) days"
    end
    
    # Get date range for the title
    start_date = minimum(working_df.date)
    end_date = maximum(working_df.date)
    date_range_str = "$(Dates.format(start_date, "yyyy-mm-dd")) to $(Dates.format(end_date, "yyyy-mm-dd"))"
    
    # Create the plot
    try
        # Use explicit Array constructors to ensure numeric types
        plot_dates = Array{Date}(working_df.date)
        plot_counts = Array{Int}(working_df.commit_count)
        
        fig = Figure(size=(900, 500))
        ax = Axis(fig[1, 1],
                 title="Organization-Wide Commit Activity ($date_range_str)",
                 xlabel="Date", 
                 ylabel="Total Commits per Day")
        
        # Use lines! with explicit arrays
        lines!(ax, plot_dates, plot_counts, color=:darkorange, linewidth=2)
        
        # Set proper date formatting
        ax.xticklabelrotation = π/4
        
        # Set y-axis limits
        max_count = maximum(plot_counts)
        ylims!(ax, (0, max_count * 1.1))
        
        # Save the plot
        _save_plot(fig, "overall_commit_activity", config.output_dir, logger)
        @info "Successfully created commit activity plot"
    catch e
        @error "Error creating commit activity plot" exception=(e, catch_backtrace())
        
        # Create a fallback text-based visualization
        try
            fig = Figure(size=(800, 400))
            commits_text = "Total commits: $total_commits\nDate range: $date_range_str"
            MakieLabel(fig[1, 1], "Commit Activity Summary\n\n$commits_text", 
                     fontsize=16, tellwidth=false, tellheight=false)
            _save_plot(fig, "overall_commit_activity", config.output_dir, logger)
        catch e2
            @error "Even fallback visualization failed" exception=e2
        end
    end
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
     MakieLabel(ga[0, 1], "Overall Issue Distribution ($total_issues Total)", fontsize=20, tellwidth=false)
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
      MakieLabel(ga[1, 1], summary_text, justification=:left, valign=:top, halign=:left, padding=(15,15,15,15), tellheight=false)
      labels = ["Open", "Merged", "Closed"]; pr_pie_values = [total_open, total_merged, total_closed]; colors = [:darkorange, :forestgreen, :firebrick]
      if total_pr > 0
          ax_pie = Axis(ga[1, 2], aspect = DataAspect()); pie!(ax_pie, pr_pie_values, color=colors, strokecolor=:white, strokewidth=2)
          hidedecorations!(ax_pie); hidespines!(ax_pie)
          MakieLabel(ga[0, 2], "PR Status Distribution", fontsize=16, tellwidth=false, halign=:center)
          elements = [PolyElement(polycolor = c) for c in colors]; legend_labels = ["$(labels[i]): $(pr_pie_values[i])" for i in 1:length(labels)]
          Legend(ga[2, 2], elements, legend_labels, valign=:top, halign = :center, orientation=:horizontal)
      else MakieLabel(ga[1, 2], "No Pull Request data found.", halign=:center, valign=:center) end
      colgap!(ga, 20); rowgap!(ga, 5)
      _save_plot(fig, "pull_request_summary", config.output_dir, logger)
end

function _plot_language_distribution_pie(lang_df::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    if isempty(lang_df) || nrow(lang_df) == 0 
        @info "No language data. Skipping language pie chart."
        return
    end
    
    # Make sure our dataframe has the expected columns
    if !(:language in propertynames(lang_df)) || !(:count in propertynames(lang_df))
        @error "Language DataFrame missing required columns (language, count). Skipping pie chart."
        return
    end
    
    # Copy the dataframe to avoid modifying the original
    working_df = copy(lang_df)
    
    # Handle missing values
    if Missing <: eltype(working_df.language)
        @warn "Language DataFrame contains missing values, filtering them out."
        working_df = filter(:language => !ismissing, working_df)
    end
    
    # Check if we have data after filtering
    if isempty(working_df)
        @info "No valid language data after filtering. Skipping language pie chart."
        return
    end
    
    # Sort and take the most common languages
    max_langs_in_pie = 10
    sorted_langs = sort(working_df, :count, rev=true)
    
    # Get our labels and values
    if nrow(sorted_langs) > max_langs_in_pie
        top_n = sorted_langs[1:max_langs_in_pie, :]
        other_count = sum(sorted_langs[(max_langs_in_pie + 1):end, :count])
        pie_labels = Vector{String}(top_n.language)
        pie_values = Vector{Int}(top_n.count)
        push!(pie_labels, "Other")
        push!(pie_values, other_count)
    else
        pie_labels = Vector{String}(sorted_langs.language)
        pie_values = Vector{Int}(sorted_langs.count)
    end
    
    # Filter out zero values
    nonzero_idx = findall(pie_values .> 0)
    if isempty(nonzero_idx)
        @info "All language counts are zero. Skipping language pie chart."
        return
    end
    
    pie_labels = pie_labels[nonzero_idx]
    pie_values = pie_values[nonzero_idx]
    
    # Handle the special case of only one language
    if length(pie_labels) == 1
        @info "Only one language found ($(pie_labels[1])). Creating a text display instead of pie chart."
        fig = Figure(size = (600, 300))
        MakieLabel(fig[1, 1], "Primary Language: $(pie_labels[1]) ($(pie_values[1]) repos)", 
                  fontsize=24, tellwidth=false, tellheight=false)
        _save_plot(fig, "language_distribution_pie", config.output_dir, logger)
        return
    end
    
    # Handle the case of inconsistent array lengths with a safer color selection
    try
        # Generate a safe number of colors
        num_langs = length(pie_labels)
        
        # Create explicit colors array with the exact same length as pie_labels
        if num_langs <= 10
            # Use predefined colors for small number of languages
            base_colors = [:steelblue, :indianred, :seagreen, :purple, :orange, 
                          :teal, :gold, :brown, :hotpink, :gray]
            pie_colors = base_colors[1:num_langs]
        else
            # Use a color generator for more colors
            pie_colors = distinguishable_colors(num_langs, [RGB(1,1,1), RGB(0,0,0)], dropseed=true)
        end
        
        # Safety check
        @assert length(pie_labels) == length(pie_values) == length(pie_colors) "Array length mismatch"
        
        # Create the visualization
        fig = Figure(size = (700, 550))
        ga = fig[1, 1] = GridLayout()
        
        # Create the pie chart
        ax = Axis(ga[1, 1], aspect = DataAspect())
        pie!(ax, pie_values, color = pie_colors, strokecolor = :white, strokewidth = 2)
        hidedecorations!(ax)
        hidespines!(ax)
        
        # Add title and legend
        MakieLabel(ga[0, 1], "Primary Language Distribution", fontsize=20, tellwidth=false)
        
        # Create legend elements
        elements = [PolyElement(polycolor = pie_colors[i]) for i in 1:length(pie_labels)]
        legend_labels = ["$(pie_labels[i]): $(pie_values[i])" for i in 1:length(pie_labels)]
        
        # Add legend
        Legend(ga[1, 2], elements, legend_labels, "Language", valign = :center, halign = :left)
        
        # Adjust layout
        colgap!(ga, 10)
        rowgap!(ga, 5)
        
        # Save the plot
        _save_plot(fig, "language_distribution_pie", config.output_dir, logger)
        
    catch e
        # Fallback to a simple text-based visualization if the pie chart fails
        @error "Error creating language pie chart, falling back to text display" exception=(e, catch_backtrace())
        
        fig = Figure(size = (800, 400))
        lang_text = join(["$(label): $(count)" for (label, count) in zip(pie_labels, pie_values)], "\n")
        MakieLabel(fig[1, 1], "Language Distribution\n\n$lang_text", 
                 fontsize=16, tellwidth=false, tellheight=false)
        _save_plot(fig, "language_distribution_pie", config.output_dir, logger)
    end
end

"""
    _plot_issue_close_time_distribution(issue_close_times::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)

Plots a violin plot showing the distribution of time to close issues for top repositories.
This visualization helps identify repository health by showing how quickly issues are addressed.
"""
function _plot_issue_close_time_distribution(issue_close_times::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    if isempty(issue_close_times) || nrow(issue_close_times) == 0
        @info "No issue close time data available. Skipping issue close time distribution plot."
        return
    end
    
    # Verify required columns exist
    required_cols = ["repo_name", "close_time_days"]
    if !all(col -> col in names(issue_close_times), required_cols)
        @error "Issue close times DataFrame missing required columns. Expected: $required_cols, got: $(names(issue_close_times))"
        return
    end
    
    # Get top repositories by number of closed issues
    top_repos_df = combine(groupby(issue_close_times, :repo_name), nrow => :count)
    sort!(top_repos_df, :count, rev=true)
    
    # Limit to top repositories for readability
    display_count = min(config.max_repos_in_plots, nrow(top_repos_df))
    top_repos = top_repos_df.repo_name[1:display_count]
    
    # Filter data to include only top repositories
    plot_data = filter(row -> row.repo_name in top_repos, issue_close_times)
    
    # Clean repository names for display (remove owner part)
    plot_data.repo_display = [split(r, '/')[end] for r in plot_data.repo_name]
    
    # Create the figure
    fig = Figure(size = (900, 600))
    ax = Axis(fig[1, 1], 
              title = "Issue Close Time Distribution", 
              xlabel = "Repository", 
              ylabel = "Days to Close",
              xticklabelrotation = π/4)
    
    try
        # Create violin plot
        violin!(ax, plot_data.repo_display, plot_data.close_time_days, 
                show_median = true, side = :both)
        
        # Add boxplot overlay for more statistical insight
        boxplot!(ax, plot_data.repo_display, plot_data.close_time_days, 
                 show_outliers = false, show_notch = true,
                 width = 0.2, color = (:black, 0.3))
        
        # Add median values as text
        for repo in unique(plot_data.repo_display)
            repo_data = filter(row -> row.repo_display == repo, plot_data).close_time_days
            if !isempty(repo_data)
                median_val = round(median(repo_data), digits=1)
                x_pos = findfirst(r -> r == repo, unique(plot_data.repo_display))
                text!(ax, x_pos, median_val, text = "$(median_val) days", 
                      align = (:center, :bottom), fontsize = 12)
            end
        end
        
        # Limit y-axis for better visualization (exclude extreme outliers)
        close_times = plot_data.close_time_days
        q3 = quantile(close_times, 0.75)
        upper_limit = q3 * 3  # 3 times the third quartile is a reasonable upper limit
        ylims!(ax, (0, min(upper_limit, maximum(close_times))))
        
        # Save the plot
        _save_plot(fig, "issue_close_time_distribution", config.output_dir, logger)
        @info "Successfully created issue close time distribution plot"
        
    catch e
        @error "Error creating issue close time distribution plot" exception=(e, catch_backtrace())
        
        # Create a simple fallback
        try
            fig_fallback = Figure(size=(800, 400))
            median_vals = combine(groupby(plot_data, :repo_display), :close_time_days => median => :median_days)
            sort!(median_vals, :median_days)
            
            ax_fallback = Axis(fig_fallback[1, 1], 
                             title = "Median Issue Close Times", 
                             xlabel = "Repository", 
                             ylabel = "Median Days to Close",
                             xticklabelrotation = π/4)
            
            barplot!(ax_fallback, median_vals.repo_display, median_vals.median_days, 
                    color = :steelblue)
            
            _save_plot(fig_fallback, "issue_close_time_medians", config.output_dir, logger)
        catch e2
            @error "Even fallback visualization failed" exception=e2
        end
    end
end

"""
    _plot_issue_close_time_trend(issue_close_times::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)

Plots the trend of issue close times over time, which can indicate improving or declining repository health.
This visualization shows how the time to close issues has evolved, with shorter times typically
indicating more active maintenance.
"""
function _plot_issue_close_time_trend(issue_close_times::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    if isempty(issue_close_times) || nrow(issue_close_times) < 20
        @info "Insufficient issue close time data for trend analysis. Skipping trend plot."
        return
    end
    
    # Verify required columns exist
    required_cols = ["repo_name", "close_time_days", "closed_at"]
    if !all(col -> col in names(issue_close_times), required_cols)
        @error "Issue close times DataFrame missing required columns for trend analysis. Expected: $required_cols"
        return
    end
    
    # Create a copy of the dataframe to work with
    plot_data = copy(issue_close_times)
    
    # Convert dates if needed
    if !(eltype(plot_data.closed_at) <: DateTime)
        @info "Converting closed_at dates to DateTime type"
        try
            plot_data.closed_at = DateTime.(plot_data.closed_at)
        catch e
            @error "Failed to convert closed_at to DateTime" exception=e
            return
        end
    end
    
    # Extract Date from DateTime
    plot_data.closed_date = Date.(plot_data.closed_at)
    
    # Sort by close date
    sort!(plot_data, :closed_date)
    
    # Use either last 2 years of data or all data if less than 2 years
    earliest_date = today() - Day(730) # 2 years
    filtered_data = filter(row -> row.closed_date >= earliest_date, plot_data)
    
    # If we don't have enough data points in the last 2 years, use all data
    if nrow(filtered_data) < 50
        filtered_data = plot_data
        @info "Using all available issue close data ($(nrow(filtered_data)) issues) for trend analysis"
    else
        @info "Using last 2 years of issue close data ($(nrow(filtered_data)) issues) for trend analysis"
    end
    
    # Calculate moving average (30 issue window)
    window_size = min(30, div(nrow(filtered_data), 3))
    if window_size < 5
        window_size = 5  # Minimum window size
    end
    
    moving_avg = Vector{Float64}()
    dates = Vector{Date}()
    
    # Calculate moving averages
    for i in window_size:nrow(filtered_data)
        window = filtered_data.close_time_days[(i-window_size+1):i]
        push!(moving_avg, mean(window))
        push!(dates, filtered_data.closed_date[i])
    end
    
    # Group by month and calculate statistics
    filtered_data.month = Date.(year.(filtered_data.closed_date), month.(filtered_data.closed_date), 1)
    monthly_stats = combine(groupby(filtered_data, :month), 
                           :close_time_days => mean => :mean_days,
                           :close_time_days => median => :median_days,
                           nrow => :count)
    
    # Create the plot
    try
        fig = Figure(size = (1000, 600))
        ga = fig[1, 1] = GridLayout()
        
        # Main trend plot
        ax1 = Axis(ga[1, 1], 
                  title = "Issue Close Time Trend", 
                  xlabel = "Date", 
                  ylabel = "Days to Close (Moving Avg, window=$window_size)")
        
        # Plot moving average
        lines!(ax1, dates, moving_avg, color = :royalblue, linewidth = 2)
        
        # Add monthly stats as scatter points
        scatter!(ax1, monthly_stats.month, monthly_stats.median_days, 
                color = :indianred, markersize = 8 .* sqrt.(monthly_stats.count / maximum(monthly_stats.count)),
                label = "Monthly Median")
        
        # Add improving/worsening indicator
        if length(moving_avg) > 10
            first_avg = mean(moving_avg[1:div(length(moving_avg), 5)])
            last_avg = mean(moving_avg[end-div(length(moving_avg), 5):end])
            change_pct = round((last_avg - first_avg) / first_avg * 100, digits=1)
            
            if abs(change_pct) > 5  # Only show if change is significant
                direction = change_pct > 0 ? "increased" : "decreased"
                health = change_pct > 0 ? "slower" : "faster"
                
                annotation_text = "Issue close time has $direction by $(abs(change_pct))%\n(issues are being closed $health)"
                
                text!(ax1, dates[end-div(length(dates), 4)], 
                      maximum(moving_avg) * 0.8, 
                      text = annotation_text, 
                      fontsize = 14, 
                      align = (:center, :center),
                      color = change_pct > 0 ? :firebrick : :forestgreen)
            end
        end
        
        # Add monthly issue count subplot
        ax2 = Axis(ga[2, 1], 
                  xlabel = "Date", 
                  ylabel = "Issues Closed/Month")
        
        barplot!(ax2, monthly_stats.month, monthly_stats.count, color = :steelblue)
        
        # Link x-axes
        linkyaxes!(ax1, ax2)
        
        # Set x limits to the same range
        date_range = (minimum(dates), maximum(dates))
        xlims!(ax1, date_range)
        xlims!(ax2, date_range)
        
        # Layout adjustments
        rowsize!(ga, 1, 0.7)
        rowsize!(ga, 2, 0.3)
        rowgap!(ga, 5)
        
        # Save the plot
        _save_plot(fig, "issue_close_time_trend", config.output_dir, logger)
        @info "Successfully created issue close time trend plot"
        
    catch e
        @error "Error creating issue close time trend plot" exception=(e, catch_backtrace())
        
        # Create a simple fallback plot
        try
            fig_fallback = Figure(size = (800, 400))
            ax = Axis(fig_fallback[1, 1], 
                     title = "Monthly Median Issue Close Times", 
                     xlabel = "Month", 
                     ylabel = "Median Days to Close")
            
            barplot!(ax, string.(monthly_stats.month), monthly_stats.median_days, color = :steelblue)
            ax.xticklabelrotation = π/4
            
            _save_plot(fig_fallback, "issue_close_time_trend_simple", config.output_dir, logger)
        catch e2
            @error "Even fallback visualization failed" exception=e2
        end
    end
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
    
    # Get issue close time data if available
    issue_close_times_df = isdefined(processed_data, :issue_close_times) ? processed_data.issue_close_times : DataFrame()

    # Call individual plot functions safely
    try _plot_repo_stars(repo_metrics_list, config, logger) catch e @error "Failed: _plot_repo_stars" exception=(e, catch_backtrace()) end
    try _plot_monthly_commits(repo_metrics_list, config, logger) catch e @error "Failed: _plot_monthly_commits" exception=(e, catch_backtrace()) end
    try _plot_issue_status_stacked(repo_metrics_list, config, logger) catch e @error "Failed: _plot_issue_status_stacked" exception=(e, catch_backtrace()) end
    try _plot_overall_commit_activity(overall_commit_activity_df, config, logger) catch e @error "Failed: _plot_overall_commit_activity" exception=(e, catch_backtrace()) end
    try _plot_top_contributors(contrib_summary_df, config, logger) catch e @error "Failed: _plot_top_contributors" exception=(e, catch_backtrace()) end
    try _plot_overall_issue_distribution_pie(repo_metrics_list, config, logger) catch e @error "Failed: _plot_overall_issue_distribution_pie" exception=(e, catch_backtrace()) end
    try _plot_pr_summary(pr_metrics_list, config, logger) catch e @error "Failed: _plot_pr_summary" exception=(e, catch_backtrace()) end
    try _plot_language_distribution_pie(language_df, config, logger) catch e @error "Failed: _plot_language_distribution_pie" exception=(e, catch_backtrace()) end
    
    # Add the new issue close time distribution plot
    if !isempty(issue_close_times_df)
        try _plot_issue_close_time_distribution(issue_close_times_df, config, logger) 
        catch e @error "Failed: _plot_issue_close_time_distribution" exception=(e, catch_backtrace()) 
        end
        
        # Add the new issue close time trend plot
        try _plot_issue_close_time_trend(issue_close_times_df, config, logger)
        catch e @error "Failed: _plot_issue_close_time_trend" exception=(e, catch_backtrace())
        end
    else
        @info "No issue close time data available for visualization."
    end

    @info "Visualizations generation attempted. Check logs for success/failure of individual plots."
    set_theme!() # Reset theme
end