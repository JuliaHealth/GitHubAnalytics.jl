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
     
     # Create a clean, professional stacked bar chart following example image
     fig_stacked = Figure(size=(1200, 800))
     ax_stacked = Axis(fig_stacked[1, 1],
                   title = "Issue Status Distribution (Stacked)",
                   xlabel = "",
                   ylabel = "Number of Issues",
                   xticklabelrotation = π/4,
                   xticklabelalign = (:right, :center))
     
     # Create positions on x-axis
     bar_positions = collect(1:display_count)
     
     # Add grid lines for better readability
     ax_stacked.xgridvisible = false
     ax_stacked.ygridvisible = true
     ax_stacked.ygridcolor = (:black, 0.1)
     
     # Calculate max value for y-axis limit
     max_issues = maximum(total_issues)
     y_limit = ceil(max_issues * 1.1 / 100) * 100  # Round to nearest 100 above max
     
     # First draw the closed issues as the base of the stacked bar
     barplot!(ax_stacked, bar_positions, closed_issues, color = :royalblue)
     
     # Then draw open issues stacked on top
     for i in 1:display_count
         # Only add open issues bar if there are any
         if open_issues[i] > 0
             # Create a small rectangle for each open issue segment
             rect = Rect(bar_positions[i] - 0.4, closed_issues[i], 0.8, open_issues[i])
             poly!(ax_stacked, rect, color = :indianred)
         end
     end
     
     # Add legend elements
     elements = [PolyElement(polycolor = c) for c in [:royalblue, :indianred]]
     legend_labels = ["Closed Issues", "Open Issues"]
     Legend(fig_stacked[1, 1, TopRight()], elements, legend_labels, framevisible = false)
     
     # Fix the negative values issue by explicitly setting y limits to start at 0
     ylims!(ax_stacked, (0, y_limit))
     
     # Set axis properties
     ax_stacked.xticks = (bar_positions, repo_names)
     
     # Fix the legend marker that was appearing at -100
     # Instead of using scatter with off-screen points, we use PolyElement for both legend entries
     
     # Save the improved stacked version
     _save_plot(fig_stacked, "issue_status_stacked", config.output_dir, logger)
     
     # Create percentage distribution chart as well
     if any(total_issues .> 0)
         open_pct = [m.open_issues / m.total_issues for m in plot_metrics]
         closed_pct = [m.closed_issues / m.total_issues for m in plot_metrics]
         
         fig_pct = Figure(size=(1200, 800))
         ax_pct = Axis(fig_pct[1, 1],
                    title = "Issue Status Distribution (Percentage)",
                    xlabel = "",
                    ylabel = "Percentage of Issues",
                    xticklabelrotation = π/4,
                    xticklabelalign = (:right, :center))
         
         # Add grid lines
         ax_pct.xgridvisible = false
         ax_pct.ygridvisible = true
         ax_pct.ygridcolor = (:black, 0.1)
         
         # Draw closed issue percentages
         barplot!(ax_pct, bar_positions, closed_pct, color = :royalblue)
         
         # Draw open issue percentages on top
         for i in 1:display_count
             # Only add open issues if there are any
             if open_pct[i] > 0
                 rect = Rect(bar_positions[i] - 0.4, closed_pct[i], 0.8, open_pct[i])
                 poly!(ax_pct, rect, color = :indianred)
             end
         end
         
         # Add legend
         Legend(fig_pct[1, 1, TopRight()], elements, legend_labels, framevisible = false)
         
         # Set axis properties
         ax_pct.xticks = (bar_positions, repo_names)
         ylims!(ax_pct, (0, 1.0))
         
         # Show percentages on y-axis
         ax_pct.yticks = (0:0.2:1.0, ["0%", "20%", "40%", "60%", "80%", "100%"])
         
         _save_plot(fig_pct, "issue_status_percentage", config.output_dir, logger)
     end
     
     # We'll keep the separate bars visualization as an additional option
     return
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

Plots a bar chart showing the median time to close issues for top repositories.
This visualization helps identify repository health by showing how quickly issues are addressed.
"""
function _plot_issue_close_time_distribution(issue_close_times::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    if isempty(issue_close_times) || nrow(issue_close_times) < 5
        @info "No or insufficient issue close time data available. Skipping issue close time distribution plot."
        return
    end
    
    # Verify required columns exist
    required_cols = ["repo_name", "close_time_days"]
    if !all(col -> col in names(issue_close_times), required_cols)
        @error "Issue close times DataFrame missing required columns. Expected: $required_cols, got: $(names(issue_close_times))"
        return
    end
    
    # Get top repositories by number of closed issues
    top_repos_df = combine(groupby(issue_close_times, :repo_name), 
                          nrow => :issue_count,
                          :close_time_days => median => :median_days,
                          :close_time_days => mean => :mean_days)
    
    # Filter to repos with at least 3 issues
    top_repos_df = filter(row -> row.issue_count >= 3, top_repos_df)
    
    if nrow(top_repos_df) == 0
        @info "No repositories with sufficient issue data for close time analysis."
        return
    end
    
    # Sort by median time to close
    sort!(top_repos_df, :median_days)
    
    # Limit to top repositories for readability
    display_count = min(config.max_repos_in_plots, nrow(top_repos_df))
    top_repos_df = top_repos_df[1:display_count, :]
    
    # Clean repository names for display (remove owner part)
    top_repos_df.repo_display = String.([split(r, '/')[end] for r in top_repos_df.repo_name])
    
    # Create the bar chart visualization
    _plot_issue_close_time_bar(issue_close_times, top_repos_df, config, logger)
    
    # Try to create a violin plot as well
    try
        _plot_issue_close_time_violin(issue_close_times, top_repos_df, config, logger)
    catch e
        @error "Failed to create violin plot for issue close times" exception=(e, catch_backtrace())
    end
end

function _plot_issue_close_time_bar(issue_close_times::DataFrame, top_repos_df::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    # Create the figure with improved styling
    fig = Figure(size = (1200, 800))
    
    # Create median time plot
    ax1 = Axis(fig[1, 1], 
              title = "Median Issue Close Times by Repository",
              xlabel = "Repository", 
              ylabel = "Days to Close (Median)",
              xticklabelrotation = π/4,
              xticklabelalign = (:right, :center))
    
    # Add grid lines
    ax1.xgridvisible = false
    ax1.ygridvisible = true
    ax1.ygridcolor = (:black, 0.1)
    
    # Create numeric x positions for barplot
    x = 1:nrow(top_repos_df)
    
    # Calculate max for y limit
    max_days = maximum(max.(top_repos_df.median_days, top_repos_df.mean_days))
    y_limit = ceil(max_days * 1.2)  # Give 20% extra space for labels
    
    # Bar plot of median days with improved styling
    bars = barplot!(ax1, x, top_repos_df.median_days, color = :royalblue)
    
    # Set custom x ticks with repository names
    ax1.xticks = (x, top_repos_df.repo_display)
    
    # Add issue count as text labels
    for (i, count) in enumerate(top_repos_df.issue_count)
        text!(ax1, i, 1, text = "$(count) issues", 
              align = (:center, :bottom), fontsize = 12,
              rotation = π/2, color = :black)
    end
    
    # Add means as points for comparison
    scatter!(ax1, x, top_repos_df.mean_days, 
            color = :firebrick, markersize = 10,
            label = "Mean")
    
    # Legend
    Legend(fig[1, 1, TopRight()], [PolyElement(polycolor = :royalblue), MarkerElement(color=:firebrick, marker=:circle)], 
           ["Median", "Mean"], framevisible = false)
    
    # Set y limit
    ylims!(ax1, (0, y_limit))
    
    # Save the plot
    _save_plot(fig, "issue_close_time_distribution", config.output_dir, logger)
    @info "Successfully created issue close time bar distribution plot"
end

function _plot_issue_close_time_violin(issue_close_times::DataFrame, top_repos_df::DataFrame, config::AnalyticsConfig, logger::AbstractLogger)
    # First prepare data for violin plot - we need to gather all the issue close times for each repo
    violin_data = Dict{String, Vector{Float64}}()
    
    for repo in top_repos_df.repo_name
        # Extract data for this repository
        repo_data = filter(row -> row.repo_name == repo, issue_close_times)
        violin_data[repo] = repo_data.close_time_days
    end
    
    # Create figure for violin plot
    fig = Figure(size = (1200, 800))
    
    ax = Axis(fig[1, 1],
             title = "Issue Close Time Distribution by Repository",
             xlabel = "Repository",
             ylabel = "Days to Close",
             xticklabelrotation = π/4,
             xticklabelalign = (:right, :center))
    
    # Add grid lines
    ax.xgridvisible = false
    ax.ygridvisible = true
    ax.ygridcolor = (:black, 0.1)
    
    # Calculate overall statistics for y-axis scaling
    all_times = vcat(values(violin_data)...)
    
    if isempty(all_times)
        @info "No close time data for violin plot"
        return
    end
    
    # Calculate percentiles for better y-axis limits (excludes extreme outliers)
    q3 = quantile(all_times, 0.75)
    upper_limit = q3 * 3  # Show up to 3x the third quartile
    y_max = min(maximum(all_times), upper_limit)
    
    # Create numeric positions
    x_positions = 1:length(top_repos_df.repo_display)
    
    # Create violin plots - one per repository
    for (i, repo) in enumerate(top_repos_df.repo_name)
        display_name = top_repos_df.repo_display[i]
        data = violin_data[repo]
        
        if length(data) >= 3  # Only plot if we have enough data points
            # Fix: Create violins one by one, using positions instead of strings
            try
                density!(ax, fill(x_positions[i], length(data)), data, 
                        orientation = :vertical,
                        color = (:royalblue, 0.6), 
                        strokecolor = :black, 
                        strokewidth = 1,
                        side = :both)
                        
                # Add median line
                median_val = median(data)
                lines!(ax, [x_positions[i]-0.3, x_positions[i]+0.3], [median_val, median_val], 
                      color = :black, linewidth = 2)
                
                # Add median value as text 
                text!(ax, x_positions[i], median_val, 
                      text = "$(round(Int, median_val))", 
                      align = (:center, :bottom), 
                      fontsize = 10, 
                      color = :black)
                      
                # Add issue count
                text!(ax, x_positions[i], minimum(data), 
                      text = "n=$(length(data))", 
                      align = (:center, :top), 
                      fontsize = 10,
                      rotation = π/2, 
                      color = :black)
            catch e
                @warn "Failed to create violin for $(display_name)" exception=e
            end
        end
    end
    
    # Set the x-ticks to display repository names
    ax.xticks = (x_positions, top_repos_df.repo_display)
    
    # Set y limits to make visualization more readable
    ylims!(ax, (0, y_max))
    
    # Save the plot
    _save_plot(fig, "issue_close_time_violin", config.output_dir, logger)
    @info "Successfully created issue close time violin plot"
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
    
    # Group by quarter to make the trend more readable
    filtered_data.quarter = [Date(year(d), 3*ceil(Int, month(d)/3), 1) for d in filtered_data.closed_date]
    
    # Calculate quarterly stats
    quarterly_stats = combine(groupby(filtered_data, :quarter), 
                            :close_time_days => mean => :mean_days,
                            :close_time_days => median => :median_days,
                            nrow => :count)
    
    # Ensure we have enough quarters to plot
    if nrow(quarterly_stats) < 3
        @info "Not enough quarterly data points for trend analysis."
        return
    end
    
    # Sort by quarter
    sort!(quarterly_stats, :quarter)
    
    # Create quarter labels in a readable format
    quarter_labels = [string(year(q), " Q", ceil(Int, month(q)/3)) for q in quarterly_stats.quarter]
    
    # Create improved plot with better styling
    try
        fig = Figure(size = (1200, 800))
        
        # Layout with proper spacing
        gl = GridLayout(fig[1, 1])
        
        # Main trend plot - taking more vertical space
        ax1 = Axis(gl[1, 1], 
                  title = "Issue Close Time Quarterly Trend",
                  ylabel = "Days to Close",
                  xticklabelrotation = π/4,
                  xticklabelalign = (:right, :center))
        
        # Better grid styling
        ax1.xgridvisible = false
        ax1.ygridvisible = true
        ax1.ygridcolor = (:black, 0.1)
        
        # Use numeric positions for x-axis
        x_numeric = 1:nrow(quarterly_stats)
        
        # Calculate y limit based on data
        max_days = maximum(max.(quarterly_stats.median_days, quarterly_stats.mean_days))
        y_limit = ceil(max_days * 1.2)  # 20% extra space
        
        # Plot median line with improved styling
        lines!(ax1, x_numeric, quarterly_stats.median_days, 
              color = :royalblue, linewidth = 3)
              
        # Add markers
        scatter!(ax1, x_numeric, quarterly_stats.median_days,
                color = :royalblue, markersize = 10, 
                label = "Median")
        
        # Plot mean line with improved styling
        lines!(ax1, x_numeric, quarterly_stats.mean_days, 
              color = :firebrick, linewidth = 3)
              
        # Add markers
        scatter!(ax1, x_numeric, quarterly_stats.mean_days,
                color = :firebrick, markersize = 10, 
                marker = :diamond, label = "Mean")
        
        # Set x labels
        ax1.xticks = (x_numeric, quarter_labels)
        
        # Set y limit
        ylims!(ax1, (0, y_limit))
        
        # Add issue count as bar chart at bottom
        ax2 = Axis(gl[2, 1], 
                  xlabel = "Quarter", 
                  ylabel = "Issues Closed",
                  xticklabelrotation = π/4,
                  xticklabelalign = (:right, :center))
        
        # Style the count chart
        ax2.xgridvisible = false
        ax2.ygridvisible = true
        ax2.ygridcolor = (:black, 0.1)
        
        # Plot issue counts
        barplot!(ax2, x_numeric, quarterly_stats.count, color = :steelblue)
        
        # Set x labels
        ax2.xticks = (x_numeric, quarter_labels)
        
        # Add trend indicator text if we have enough data points
        if nrow(quarterly_stats) >= 4
            # Calculate trend by comparing first and last quarters
            first_quarters = quarterly_stats.median_days[1:2]
            last_quarters = quarterly_stats.median_days[end-1:end]
            
            first_avg = mean(first_quarters)
            last_avg = mean(last_quarters)
            
            change_pct = round((last_avg - first_avg) / first_avg * 100, digits=1)
            
            if abs(change_pct) > 5  # Only show if change is significant
                direction = change_pct > 0 ? "increased" : "decreased"
                health = change_pct > 0 ? "slower" : "faster"
                
                # Create a text box with a clear background
                box_width = 0.25 * length(x_numeric)
                box_height = 0.15 * y_limit
                box_x = 1
                box_y = 0.75 * y_limit
                
                # Add white background to text for better readability
                poly!(ax1, Rect(box_x, box_y - box_height/2, box_width, box_height), 
                     color = (:white, 0.9), strokecolor = :gray, strokewidth = 1)
                
                # Place text over the background
                text!(ax1, box_x + box_width/2, box_y, 
                     text = "Issue close time has $direction\nby $(abs(change_pct))%\n(issues are being closed $health)", 
                     fontsize = 16, 
                     align = (:center, :center),
                     color = change_pct > 0 ? :firebrick : :forestgreen)
            end
        end
        
        # Add legend with better positioning
        Legend(gl[1, 1, TopRight()], ax1, framevisible = false)
        
        # Layout adjustments for proper spacing
        rowsize!(gl, 1, 0.7)  # Top row (trend) gets 70% of space
        rowsize!(gl, 2, 0.3)  # Bottom row (counts) gets 30% of space
        rowgap!(gl, 10)       # Gap between plots
        
        # Save the plot
        _save_plot(fig, "issue_close_time_trend", config.output_dir, logger)
        @info "Successfully created issue close time trend plot"
        
    catch e
        @error "Error creating issue close time trend plot" exception=(e, catch_backtrace())
        
        # Create a simplified fallback plot
        try
            fig_fallback = Figure(size = (800, 500))
            ax = Axis(fig_fallback[1, 1], 
                     title = "Quarterly Median Issue Close Times", 
                     xlabel = "Quarter", 
                     ylabel = "Median Days to Close",
                     xticklabelrotation = π/4,
                     xticklabelalign = (:right, :center))
            
            # Use numeric indices for barplot
            x_numeric = 1:length(quarter_labels)
            barplot!(ax, x_numeric, quarterly_stats.median_days, color = :royalblue)
            ax.xticks = (x_numeric, quarter_labels)
            
            # Style improvements
            ax.xgridvisible = false
            ax.ygridvisible = true
            ax.ygridcolor = (:black, 0.1)
            
            _save_plot(fig_fallback, "issue_close_time_trend_simple", config.output_dir, logger)
        catch e2
            @error "Fallback visualization also failed" exception=e2
        end
    end
end

# --- Main Plotting Function ---
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

    # Call individual plot functions safely - make sure to keep all original plots
    try _plot_repo_stars(repo_metrics_list, config, logger) catch e @error "Failed: _plot_repo_stars" exception=(e, catch_backtrace()) end
    try _plot_monthly_commits(repo_metrics_list, config, logger) catch e @error "Failed: _plot_monthly_commits" exception=(e, catch_backtrace()) end
    try _plot_issue_status_stacked(repo_metrics_list, config, logger) catch e @error "Failed: _plot_issue_status_stacked" exception=(e, catch_backtrace()) end
    try _plot_overall_commit_activity(overall_commit_activity_df, config, logger) catch e @error "Failed: _plot_overall_commit_activity" exception=(e, catch_backtrace()) end
    try _plot_top_contributors(contrib_summary_df, config, logger) catch e @error "Failed: _plot_top_contributors" exception=(e, catch_backtrace()) end
    try _plot_overall_issue_distribution_pie(repo_metrics_list, config, logger) catch e @error "Failed: _plot_overall_issue_distribution_pie" exception=(e, catch_backtrace()) end
    try _plot_pr_summary(pr_metrics_list, config, logger) catch e @error "Failed: _plot_pr_summary" exception=(e, catch_backtrace()) end
    try _plot_language_distribution_pie(language_df, config, logger) catch e @error "Failed: _plot_language_distribution_pie" exception=(e, catch_backtrace()) end
    
    # Add the issue close time plots only if we have data
    if !isempty(issue_close_times_df)
        try _plot_issue_close_time_distribution(issue_close_times_df, config, logger) 
        catch e @error "Failed: _plot_issue_close_time_distribution" exception=(e, catch_backtrace()) 
        end
        
        try _plot_issue_close_time_trend(issue_close_times_df, config, logger)
        catch e @error "Failed: _plot_issue_close_time_trend" exception=(e, catch_backtrace())
        end
    else
        @info "No issue close time data available for visualization."
    end

    @info "Visualizations generation attempted. Check logs for success/failure of individual plots."
    set_theme!() # Reset theme
end