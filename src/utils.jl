# src/utils.jl
using Logging, LoggingExtras, Dates

"""
    setup_logger(config::AnalyticsConfig) -> AbstractLogger

Sets up the logging infrastructure based on the configuration.

Creates a TeeLogger to log both to the console and a timestamped file
in the output directory. The log level is determined by `config.log_level`
unless `config.verbose` is true, in which case it's set to Debug.
"""
function setup_logger(config::AnalyticsConfig)
    log_level = config.verbose ? Logging.Debug : config.log_level
    # Ensure output directory exists for the log file
    mkpath(config.output_dir)
    timestamp = Dates.format(now(), "yyyy-mm-dd_HHMMSS")
    log_file = joinpath(config.output_dir, "github_analytics_$(timestamp).log")
    # Create file logger (using MinLevelLogger to filter)
    file_logger = MinLevelLogger(FileLogger(log_file), log_level)
    # Create console logger (using MinLevelLogger to filter)
    console_logger = MinLevelLogger(ConsoleLogger(stderr), log_level)
    # Combine them with TeeLogger
    logger = TeeLogger(file_logger, console_logger)
    return logger
end

"""
    debug_commit_activity(pd::ProcessedData)

Debug utility function that prints information about the commit activity data.
This function helps diagnose issues with empty commit activity plots.

Call this function after generating the ProcessedData object if you're having
issues with the commit activity visualization.
"""
function debug_commit_activity(pd::ProcessedData)
    commit_df = pd.overall_commit_activity
    
    println("--- Commit Activity Data Debug ---")
    println("Number of days with commit data: $(nrow(commit_df))")
    
    if isempty(commit_df)
        println("ERROR: Commit activity DataFrame is empty!")
        return
    end
    
    total_commits = sum(commit_df.commit_count)
    println("Total commits: $total_commits")
    
    if total_commits == 0
        println("ERROR: No commits found in the data!")
    end
    
    date_range = if !isempty(commit_df)
        min_date = minimum(commit_df.date)
        max_date = maximum(commit_df.date)
        "$(min_date) to $(max_date) ($(max_date - min_date) days)"
    else
        "N/A (no data)"
    end
    println("Date range: $date_range")
    
    # Print the top 5 days with most commits
    if nrow(commit_df) > 0
        sorted_df = sort(commit_df, :commit_count, rev=true)
        top_days = min(5, nrow(sorted_df))
        println("\nTop $top_days days with most commits:")
        for i in 1:top_days
            println("  $(sorted_df.date[i]): $(sorted_df.commit_count[i]) commits")
        end
    end
    
    # Check config settings
    println("\nFetch commit history enabled: $(pd.config.fetch_commit_history)")
    println("Commit history months setting: $(pd.config.commit_history_months)")
    
    # Check unique repositories with commits
    repos_with_commits = sum(rm.total_commits_fetched_period > 0 for rm in values(pd.repo_metrics))
    println("Repositories with commit data: $repos_with_commits / $(length(pd.repo_metrics))")
    
    println("--- End Debug Info ---")
end

# Export the debug function
export debug_commit_activity

# Add other utility functions here if needed later, e.g.,
# function handle_github_api_error(e, context_message, logger) ...
# function format_repo_name(owner, repo) ...
