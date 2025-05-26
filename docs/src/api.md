# Here goes information about integrating the MedImages API with your backend

````markdown
# API Reference

## Configuration

### `AnalyticsConfig`

The main configuration struct for setting up your GitHub analysis.

```julia
AnalyticsConfig(;
    targets::Vector{String},
    auth_token::String,
    output_dir::String = "github_analysis",
    log_level = Logging.Info,
    fetch_contributors::Bool = true,
    fetch_commit_history::Bool = true,
    fetch_pull_requests::Bool = true,
    generate_plots::Bool = true,
    generate_csv::Bool = true,
    generate_markdown::Bool = true
)
```

**Parameters:**
- `targets`: Vector of GitHub usernames/organizations or repository names to analyze
- `auth_token`: GitHub personal access token for API access
- `output_dir`: Directory where results will be saved
- `log_level`: Logging level for output verbosity
- `fetch_contributors`: Whether to fetch contributor data
- `fetch_commit_history`: Whether to fetch commit history
- `fetch_pull_requests`: Whether to fetch pull request data
- `generate_plots`: Whether to generate visualization plots
- `generate_csv`: Whether to export data as CSV files
- `generate_markdown`: Whether to generate markdown reports

## Main Functions

### `run_analysis(config::AnalyticsConfig)`

Main function to execute the GitHub analytics pipeline.

**Returns:** `ProcessedData` struct containing all analyzed results

### `generate_markdown_summary(processed_data, config, logger)`

Generate comprehensive markdown reports from processed data.

### `generate_csv_reports(processed_data, config, logger)`

Export data to CSV format for further analysis.

## Data Structures

### `ProcessedData`

Container for all processed analytics data including:
- Repository metrics
- Issue analysis
- Pull request metrics  
- Contributor summaries
- Language distribution
- Commit activity data

### `RepositoryMetrics`

Individual repository statistics including stars, forks, issues, and basic metadata.

### `PullRequestMetrics`

Pull request analysis data including merge rates, review times, and status distributions.

## Authentication

GitHubAnalytics.jl requires a GitHub personal access token for API access. Set this as an environment variable:

```bash
export GITHUB_TOKEN="your_token_here"
```

Or pass it directly to the configuration:

```julia
config = AnalyticsConfig(
    targets = ["your_target"],
    auth_token = "your_token_here",
    # ... other options
)
```

## Output Files

The package generates several types of output files:

- **Markdown Reports**: Comprehensive analysis summaries
- **CSV Data**: Raw data for custom analysis
- **Visualizations**: PNG charts and plots
- **JSON Data**: Structured data for programmatic access