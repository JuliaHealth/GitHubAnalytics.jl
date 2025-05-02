module BasicStructs
# src/structs.jl
using Dates

export RepoBasicInfo, RepoMetrics, ContributorMetrics, CommitHistoryEntry, PullRequestMetrics

# --- Renamed and Simplified Base Info ---
"""
    RepoBasicInfo

Basic information fetched directly for a repository. More detailed metrics
are stored in `RepoMetrics`.
"""
struct RepoBasicInfo
    name::String # Full name "owner/repo"
    owner_login::String
    repo_name_short::String # Just the repo part
    description::Union{String, Nothing}
    stars::Int
    forks::Int
    primary_language::Union{String, Nothing}
    created_at::DateTime
    updated_at::DateTime # Last push/update time reported by API
    is_fork::Bool
    is_archived::Bool
    # Add other simple fields if needed: watchers_count, homepage etc.
end

# --- Metrics Struct (can be built up) ---
"""
    RepoMetrics

Aggregated and calculated metrics for a single repository.
Fields are populated during different stages of fetching and processing.
Marked `mutable` to allow updates (e.g., adding calculated commit counts).
"""
mutable struct RepoMetrics
    # Basic Info derived from RepoBasicInfo
    name::String # Full name "owner/repo"
    stars::Int
    forks::Int
    created_at::DateTime
    primary_language::Union{String, Nothing}

    # Issue Metrics
    open_issues::Int
    closed_issues::Int
    total_issues::Int
    issue_resolution_rate::Union{Float64, Nothing} # Calculated

    # Commit Metrics (Calculated later)
    total_commits_fetched_period::Int # Commits within the fetched window
    monthly_commits_last30d::Int      # Commits in the most recent 30 days

    # PR Metrics (Populated later)
    # These might live solely in PullRequestMetrics, link by repo name?
    # Or mirror key PR stats here? Let's keep them separate for now.

    # Activity Metrics
    last_api_update::DateTime # Corresponds to updated_at from API
    age_days::Int             # Calculated from created_at

    # Constructor for initial population from basic info and issues
    function RepoMetrics(basic_info::RepoBasicInfo, open_issues::Int, closed_issues::Int)
        total = open_issues + closed_issues
        rate = total > 0 ? round(closed_issues / total; digits=3) : nothing
        age = Dates.value(today() - Date(basic_info.created_at))

        # Initialize commit fields to 0 or placeholder
        new(basic_info.name, basic_info.stars, basic_info.forks, basic_info.created_at,
            basic_info.primary_language,
            open_issues, closed_issues, total, rate,
            0, 0, # Commit placeholders
            basic_info.updated_at, age
            )
    end
end

# --- Other Structs (Mostly Unchanged initially) ---

"""
    ContributorMetrics

Represents commit contributions for a single contributor to a specific repository,
as reported by the GitHub API (may include merges, etc.).
"""
struct ContributorMetrics
    repo_name::String # Full name "owner/repo"
    contributor_login::String
    commit_count::Int # "contributions" count from API
end

"""
    CommitHistoryEntry

Represents a single commit's information relevant for analysis.
"""
struct CommitHistoryEntry
    repo_name::String # Full name "owner/repo"
    sha::String
    committer_login::Union{String, Nothing}
    committer_date::DateTime
    author_login::Union{String, Nothing}
    author_date::DateTime
    message_summary::String # First line of commit message
end


"""
    PullRequestMetrics

Summary statistics for Pull Requests in a repository.
"""
struct PullRequestMetrics
    repo_name::String # Full name "owner/repo"
    open_pr_count::Int
    closed_pr_count::Int # Explicitly closed, not merged
    merged_pr_count::Int
    total_pr_count::Int # open + closed + merged
    avg_merge_time_days::Union{Float64, Nothing} # Average for merged PRs in fetched data
    # Consider adding: distribution of merge times, avg time to first comment, etc.
end
end#module BasicStructs