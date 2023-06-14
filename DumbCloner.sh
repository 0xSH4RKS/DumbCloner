#!/bin/bash

# Specify the filename
filename='YOUR_REPOS'

# Enter your GitHub token here
github_token="YOUR_GITHUB_TOKEN"

# Organization name
org_name="YOUR_ORG_NAME"

# Personal GitHub username
personal_username="YOUR_GITHUB_USERNAME"

# Target: 'org' for organization, 'personal' for personal repo
target=$1

# Validation for target argument
if [ "$target" != "org" ] && [ "$target" != "personal" ]; then
    echo "Invalid argument. Use 'org' for organization or 'personal' for personal repo."
    exit 1
fi

# Keep track of downloaded repositories
downloaded_repos='downloaded_repos.txt'

# Determine the destination based on the target
if [ "$target" == "org" ]; then
    destination=$org_name
else
    destination=$personal_username
fi

# Read the file line by line
while read repo; do
    # Get the name of the repository
    repo_name=$(basename "$repo" .git)

    # Print the repo name for debugging
    echo "Repo name: $repo_name"

    # Check if repo_name is not empty
    if [ -z "$repo_name" ]; then
        echo "Repo name is empty, skipping..."
        continue
    fi

    # Check if the repo has already been cloned
    if [ -d "$repo_name" ]; then
        echo "Repo $repo_name already cloned, skipping clone..."
    else
        # Modify the repo URL to include the GitHub token
        authenticated_repo=$(echo "$repo" | sed "s#https://#https://$github_token@#")

        # Clone the repository
        git clone "$authenticated_repo"
    fi

    # Log the downloaded repo
    echo "$repo_name" >> "$downloaded_repos"

    # Create a new repository on GitHub
    response=$(curl -s -w "\n%{http_code}" -H "Authorization: token $github_token" \
         -H "Accept: application/vnd.github.v3+json" \
         -X POST https://api.github.com/user/repos \
         -d '{"name":"'"$repo_name"'", "private": true}')

    # Check if repo creation was successful
    http_status=$(echo "$response" | tail -n1)

    # Check if HTTP status is 422 (repository already exists)
    if [ "$http_status" -eq 422 ]; then
        echo "Repository already exists, checking its visibility..."

        # Check if the repository is private
        repo_visibility=$(curl -s -H "Authorization: token $github_token" \
            https://api.github.com/repos/$destination/$repo_name \
            | jq .private)
        
        # If the repository is not private
        if [ "$repo_visibility" = "false" ]; then
            echo "Making the repository private..."
            # Make the repository private
            curl -s -H "Authorization: token $github_token" \
                 -H "Accept: application/vnd.github.v3+json" \
                 -X PATCH https://api.github.com/repos/$destination/$repo_name \
                 -d '{"private": true}'
        fi
    elif [ "$http_status" -ne 201 ]; then
        echo "Error creating repository, skipping this repo. HTTP status: $http_status"
        continue
    fi

    # Change directory to the cloned repo
    cd "$repo_name"

    # Get the name of the default branch
    default_branch=$(git symbolic-ref --short HEAD)

    # Set the new remote URL (the newly created repo)
    new_repo_url="https://$github_token@github.com/$destination/$repo_name.git"
    git remote set-url origin "$new_repo_url"

    # Push the content to the new repo
    git push origin "$default_branch"

    # Change back to the root directory
    cd ..
done < "$filename"
