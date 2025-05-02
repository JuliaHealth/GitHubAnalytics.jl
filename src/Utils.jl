module Utils
# src/utils.jl
using Logging, LoggingExtras, Dates

export setup_logger

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

# Add other utility functions here if needed later, e.g.,
# function handle_github_api_error(e, context_message, logger) ...
# function format_repo_name(owner, repo) ...

end#module Utils