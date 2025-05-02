# examples/run_live_analysis.jl

# Import the package we built
using GitHubAnalytics

# Standard libraries used by this script
using Dates
using Logging, LoggingExtras

function main()
    targets = ["JuliaAI"]
    println("--- Starting Live GitHub Analysis ---")

    # 1. Get GitHub Token from Environment Variable (Required!)
    #    This is the secure way to handle credentials.
    token = get(ENV, "GITHUB_TOKEN", "")
    if isempty(token)
        println(stderr, "ERROR: Environment variable GITHUB_TOKEN is not set.")
        println(stderr, "Please set it before running the script.")
        println(stderr, "Example (Bash): export GITHUB_TOKEN='your_personal_access_token'")
        println(stderr, "Create a token at: https://github.com/settings/tokens")
        println(stderr, "Ensure it has 'repo:public_repo' or broader 'repo' scope.")
        exit(1) # Exit if token is missing
    end
    println("Using GitHub token from environment variable.")

    # 2. Configure the Analysis
    #    Create an AnalyticsConfig object from the package.
    
    # Modified for testing: using specific repos instead of the whole organization
    # This limits testing to just 2 specific repos instead of all JuliaHealth repos
    repos_to_test = ["JuliaHealth/FHIRClient.jl", "JuliaHealth/DICOM.jl"]
    
    output_directory = "organalysis_$(Dates.format(now(), "yyyy-mm-dd_HHMMSS"))"

    config = AnalyticsConfig(
        targets = targets, # Use specific repos instead of the whole org
        auth_token = token,
        output_dir = output_directory,

        # --- Optional Settings (Defaults shown) ---
        max_repos_in_plots = 100,
        commit_history_months = 12,
        repo_processing_delay_sec = 0.25, # Adjust delay as needed (0.2-0.5 is usually safe)
        log_level = Logging.Info,      # Change to Logging.Debug for more verbose logs
        verbose = false,               # Set to true for Debug logs regardless of log_level

        # --- Fine-grained Control (Defaults are true) ---
        fetch_contributors = true,
        fetch_commit_history = true,
        fetch_pull_requests = true,
        generate_plots = true,
        generate_csv = true,
        generate_markdown = true
    )

    println("Configuration set:")
    println("  Targets: $(config.targets)")
    println("  Output Directory: $(config.output_dir)")
    println("  Log Level: $(config.verbose ? "Debug (Verbose)" : config.log_level)")
    println("---")

    # 3. Run the Analysis using the package function
    println("Starting analysis run... This may take several minutes depending on the number of repositories and rate limits.")
    start_time = now()

    # This is the main call to your package
    results = GitHubAnalytics.run_analysis(config)

    end_time = now()
    duration_minutes = round((end_time - start_time).value / 1000 / 60, digits=2)
    println("---")

    # 4. Report Completion Status
    if isnothing(results)
        println(stderr, "Analysis encountered a critical error and did not complete.")
        println(stderr, "Please check the log file inside the output directory: $(config.output_dir)")
        exit(1) # Indicate failure
    elseif isempty(results.repo_metrics) && !isempty(config.targets)
         println("Analysis completed, but no repository metrics were successfully processed.")
         println("Check logs in $(config.output_dir) for details (e.g., repository not found, API errors).")
    else
        println("Analysis finished successfully!")
        println("Duration: $duration_minutes minutes")
        println("Results saved in directory: $(config.output_dir)")
        println("Repositories analyzed: $(length(results.repo_metrics))")

        # Optionally print some key results from the returned data
        if haskey(results.overall_stats, "total_stars")
             println("Total stars across analyzed repos: $(results.overall_stats["total_stars"])")
        end
         if haskey(results.overall_stats, "total_issues")
             println("Total issues (open+closed): $(results.overall_stats["total_issues"])")
         end
    end
    println("---")

end

# Standard Julia entry point: Run main() if the script is executed directly.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end