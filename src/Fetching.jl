# src/fetching.jl
using GitHub
using Dates
using Logging

# Helper for pagination (can be reused)
function fetch_paginated_data(func::Function, args...; auth, logger, params=Dict(), context="")
    all_results = []
    try
        results, page_data = func(args...; auth=auth, params=merge(params, Dict("per_page" => 100)))
        append!(all_results, results)
        @debug "Fetched page 1 for $context" count=length(results)

        # Loop through subsequent pages if they exist
        page_count = 1
        while GitHub.has_next_page(page_data)
            page_count += 1
            @debug "Fetching page $page_count for $context"
            # Slight delay between pages? Optional.
            # sleep(0.1)
            results, page_data = GitHub.pop_next_page(page_data) # Use pop_next_page
            if !isnothing(results) && !isempty(results)
                 append!(all_results, results)
            else
                 @warn "Received empty results on page $page_count for $context, stopping pagination."
                 break # Stop if a page returns nothing or is empty
            end
            # Add safeguard against infinite loops?
            if page_count > 50 # Limit to 50 pages (5000 items) - adjust as needed
                 @warn "Stopped pagination after 50 pages for $context to prevent potential infinite loop."
                 break
            end
        end
        @debug "Finished pagination for $context. Total items: $(length(all_results))"
        return all_results
    catch e
        # Handle common errors gracefully
        if isa(e, GitHub.APIError) && e.response.status == 404
             @error "Resource not found (404) for $context: $(args[1])" repo=args[1] # Assume first arg is repo/org
        elseif isa(e, GitHub.APIError) && e.response.status == 401
             @error "Authentication failed (401) for $context. Check token permissions." repo=args[1]
        elseif isa(e, GitHub.APIError) && e.response.status == 403
             @error "Forbidden (403) for $context. Rate limit exceeded or insufficient permissions?" repo=args[1]
        elseif isa(e, GitHub.APIError) && e.response.status == 409 # Conflict (e.g., empty repo for commits)
             @warn "Conflict (409) fetching $context, likely an empty repository." repo=args[1]
        elseif isa(e, GitHub.APIError) && e.response.status == 204 # No content (e.g., contributors)
             @warn "No content (204) found for $context." repo=args[1]
        else
            # Log other errors more generally
             @error "Error fetching paginated data for $context" repo=args[1] exception=(e, catch_backtrace())
        end
        return nothing # Indicate failure
    end
end


"""
    fetch_basic_repo_info(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger) -> Union{RepoBasicInfo, Nothing}

Fetches basic repository information like stars, forks, description, dates, language.
"""
function fetch_basic_repo_info(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger)
    @debug "Fetching basic info for $repo_name"
    try
        repo_obj = GitHub.repo(repo_name; auth=auth)

        # Extract owner login and repo short name
        owner_login = repo_obj.owner.login
        repo_name_short = repo_obj.name

        basic_info = RepoBasicInfo(
            repo_name, # Use full name provided
            owner_login,
            repo_name_short,
            repo_obj.description,
            repo_obj.stargazers_count,
            repo_obj.forks_count,
            repo_obj.language, # Can be Nothing
            DateTime(repo_obj.created_at),
            DateTime(repo_obj.updated_at),
            repo_obj.fork,
            repo_obj.archived
        )
        return basic_info
    catch e
        if isa(e, GitHub.APIError) && e.response.status == 404
            @error "Repository $repo_name not found (404)."
        elseif isa(e, GitHub.APIError) # Catch other GitHub API errors
             @error "GitHub API error fetching basic info for $repo_name" status=e.response.status exception=(e, catch_backtrace())
        else
            @error "Error fetching basic info for $repo_name" exception=(e, catch_backtrace())
        end
        return nothing
    end
end

"""
    fetch_issues(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger) -> Union{Vector{GitHub.Issue}, Nothing}

Fetches all issues (open and closed) for a repository, handling pagination.
"""
function fetch_issues(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger)
    @debug "Fetching issues for $repo_name"
    # Use the helper function
    # Note: GitHub.jl's issues function takes repo name first.
    return fetch_paginated_data(GitHub.issues, repo_name;
                                auth=auth, logger=logger,
                                params=Dict("state" => "all"),
                                context="issues for $repo_name")
end

"""
    fetch_contributors(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger) -> Union{Vector{ContributorMetrics}, Nothing}

Fetches contributor statistics, handling pagination and transforming the result.
Returns `nothing` on error, potentially an empty vector if no contributors (or 204 response).
"""
function fetch_contributors(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger)
    @debug "Fetching contributors for $repo_name"
    # Note: GitHub.contributors returns Vector{Dict}
    raw_contributors = fetch_paginated_data(GitHub.contributors, repo_name;
                                           auth=auth, logger=logger,
                                           params=Dict(), # No extra params needed usually
                                           context="contributors for $repo_name")

    if isnothing(raw_contributors)
        return nothing # Error occurred during fetch
    end

    # Transform the Vector{Dict} into Vector{ContributorMetrics}
    contributor_metrics = ContributorMetrics[]
    try
        for c_dict in raw_contributors
             # Check for potential missing fields, although GitHub.jl usually handles this
             login = get(get(c_dict, "contributor", Dict()), "login", nothing) # Safer access
             contributions = get(c_dict, "contributions", nothing)

             if !isnothing(login) && !isnothing(contributions)
                 push!(contributor_metrics, ContributorMetrics(repo_name, login, contributions))
             else
                 @warn "Skipping contributor entry with missing data" repo=repo_name entry=c_dict
             end
        end
    catch e
        @error "Error processing raw contributor data for $repo_name" exception=(e, catch_backtrace())
        return nothing # Indicate processing failure
    end

    if isempty(raw_contributors) && !isempty(contributor_metrics)
        # This case shouldn't happen logically, but good to check
         @warn "Raw contributors empty but processed metrics not? Check logic." repo=repo_name
    elseif isempty(raw_contributors) && isempty(contributor_metrics)
         @debug "No contributors found or returned for $repo_name." # Could be 204 or genuinely empty
    end


    return contributor_metrics
end

"""
    fetch_commit_history(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger; since::Date) -> Union{Vector{CommitHistoryEntry}, Nothing}

Fetches commit history since a given date, handling pagination and transforming results.
"""
function fetch_commit_history(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger; since::Date)
    @debug "Fetching commit history for $repo_name since $since"
    since_str = Dates.format(since, Dates.ISODateFormat) * "T00:00:00Z" # Add time for precision

    raw_commits = fetch_paginated_data(GitHub.commits, repo_name;
                                      auth=auth, logger=logger,
                                      params=Dict("since" => since_str),
                                      context="commits for $repo_name")

    if isnothing(raw_commits)
        # Error (like 409 for empty repo) handled in fetch_paginated_data
        return nothing
    end

    commit_history = CommitHistoryEntry[]
    try
        for commit in raw_commits
            # Extract details carefully, handling potential nulls
            sha = commit.sha
            message = commit.commit.message
            message_summary = first(split(message, '\n'; limit=2)) # First line

            # Committer Info
            committer_obj = commit.commit.committer
            committer_login = isnothing(commit.committer) ? nothing : commit.committer.login # User object can be null
            committer_date = isnothing(committer_obj) || isnothing(committer_obj.date) ? DateTime(0) : DateTime(committer_obj.date)

            # Author Info (often different from committer)
            author_obj = commit.commit.author
            author_login = isnothing(commit.author) ? nothing : commit.author.login # User object can be null
            author_date = isnothing(author_obj) || isnothing(author_obj.date) ? DateTime(0) : DateTime(author_obj.date)

            if committer_date == DateTime(0) && author_date == DateTime(0)
                 @warn "Commit missing both committer and author date" repo=repo_name sha=sha
                 # Skip? Or use a placeholder? Skipping for now.
                 continue
            end
            # Prefer committer date if available, otherwise author date for sorting/filtering
            primary_date = committer_date != DateTime(0) ? committer_date : author_date

            # Basic check against 'since' date (API should handle, but double check)
             if Date(primary_date) < since
                 @warn "API returned commit older than 'since' date, skipping" repo=repo_name sha=sha commit_date=primary_date since_date=since
                 continue
             end


            push!(commit_history, CommitHistoryEntry(
                repo_name, sha, committer_login, committer_date,
                author_login, author_date, message_summary
            ))
        end
    catch e
        @error "Error processing raw commit data for $repo_name" exception=(e, catch_backtrace())
        return nothing # Indicate processing failure
    end

    return commit_history
end

"""
    fetch_pull_requests(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger) -> Union{Vector{GitHub.PullRequest}, Nothing}

Fetches all pull requests (open and closed/merged), handling pagination.
Returns the raw `GitHub.PullRequest` objects. Processing happens later.
"""
function fetch_pull_requests(repo_name::String, auth::GitHub.Authorization, logger::AbstractLogger)
    @debug "Fetching pull requests for $repo_name"
    all_prs = GitHub.PullRequest[] # Initialize empty vector

    # Fetch Open PRs
    @debug "Fetching open PRs for $repo_name"
    open_prs = fetch_paginated_data(GitHub.pull_requests, repo_name;
                                    auth=auth, logger=logger,
                                    params=Dict("state" => "open"),
                                    context="open PRs for $repo_name")
    if isnothing(open_prs)
         @warn "Failed to fetch open PRs for $repo_name. Continuing with closed PRs."
         # Decide if this is critical - maybe return nothing if *any* part fails?
         # For now, let's try to get closed ones even if open failed.
    else
         append!(all_prs, open_prs)
    end

    # Fetch Closed/Merged PRs
    @debug "Fetching closed/merged PRs for $repo_name"
    closed_prs = fetch_paginated_data(GitHub.pull_requests, repo_name;
                                      auth=auth, logger=logger,
                                      params=Dict("state" => "closed"), # includes merged
                                      context="closed/merged PRs for $repo_name")

    if isnothing(closed_prs)
         @warn "Failed to fetch closed/merged PRs for $repo_name."
         # If open PRs also failed, we have nothing. If open succeeded, return just those?
         # Let's return nothing if *any* fetch part failed for consistency.
         if isnothing(open_prs)
             return nothing
         end
         # Otherwise, we have open PRs, continue with just those (already appended).
    else
        append!(all_prs, closed_prs)
    end

    # Check if we ended up with nothing after potential partial failures
    if isempty(all_prs) && (isnothing(open_prs) || isnothing(closed_prs))
         # This means at least one fetch failed AND the other yielded nothing or also failed
         @warn "Could not retrieve any PR data for $repo_name after attempting open and closed states."
         # Return nothing if we genuinely couldn't fetch anything due to errors
         # If fetches succeeded but returned empty lists, return the empty list.
         if isnothing(open_prs) || isnothing(closed_prs)
             return nothing
         end

    end


    @debug "Total PRs fetched (open+closed+merged) for $repo_name: $(length(all_prs))"
    return all_prs
end
