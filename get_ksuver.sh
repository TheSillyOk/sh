#!/bin/bash

# ==============================================================================
# get_ksu_version.sh (v6 - Final)
#
# Description:
#   A script to extract the version number of KernelSU or a compatible fork
#   by providing its GitHub repository details. This version prioritizes
#   dynamic Git-based versioning and falls back to hardcoded values.
#
# Usage:
#   ./get_ksu_version.sh <owner> <repo> [branch]
#
# Dependencies:
#   git, curl, jq, sed, grep, bc
# ==============================================================================

# --- Strict Mode & Dependency Check ---
set -eo pipefail

for cmd in git curl jq sed grep bc; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is not installed. Please install it to continue." >&2
        exit 1
    fi
done

# --- Argument Parsing ---
if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    echo "Usage: $0 <owner> <repo> [branch]" >&2
    echo "Example: $0 KernelSU-Next KernelSU-Next next" >&2
    exit 1
fi

OWNER="$1"
REPO="$2"
BRANCH="$3"
API_URL="https://api.github.com"
REPO_URL="https://github.com/$OWNER/$REPO.git"

# --- Cleanup Function ---
cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    # echo "--> Cleaning up temporary directory..." >&2
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

TMP_DIR=""

main() {
    TMP_DIR=$(mktemp -d)

    # echo "--> Verifying repository '$OWNER/$REPO' exists..."
    HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" "$API_URL/repos/$OWNER/$REPO")
    if [[ "$HTTP_CODE" -ne 200 ]]; then
        echo "Error: Repository not found or is private (HTTP Status: $HTTP_CODE)." >&2
        echo "Please check for typos in the owner ('$OWNER') and repo ('$REPO') names." >&2
        exit 1
    fi
    # echo "--> Repository found."

    if [ -z "$BRANCH" ]; then
        # echo "--> Branch not specified. Detecting default branch..."
        DEFAULT_BRANCH=$(curl --silent -H "Accept: application/vnd.github.v3+json" "$API_URL/repos/$OWNER/$REPO" | jq -r .default_branch)
	if [[ "$DEFAULT_BRANCH" == "null" || -z "$DEFAULT_BRANCH" ]]; then
            echo "Error: Could not determine default branch." >&2
            exit 1
	fi
        BRANCH="$DEFAULT_BRANCH"

        # echo "--> Using default branch: '$BRANCH'"
    # else
        # echo "--> Using specified branch: '$BRANCH'"
    fi

    # echo "--> Fetching commit count for branch '$BRANCH'..."
    COMMIT_COUNT=$(curl --silent -I -H "Accept: application/vnd.github.v3+json" "$API_URL/repos/$OWNER/$REPO/commits?sha=$BRANCH&per_page=1" | grep -i "^link:" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p')

    if [ -z "$COMMIT_COUNT" ]; then
        # echo "--> Falling back to direct commit count for branch '$BRANCH'..."
        COMMIT_COUNT=$(curl --silent -H "Accept: application/vnd.github.v3+json" "$API_URL/repos/$OWNER/$REPO/commits?sha=$BRANCH&per_page=100" | jq '. | length')
    fi

    if ! [[ "$COMMIT_COUNT" =~ ^[0-9]+$ && "$COMMIT_COUNT" -gt 0 ]]; then
        # echo "Warning: Could not retrieve a valid commit count for '$BRANCH'. This might prevent dynamic version calculation." >&2
        COMMIT_COUNT=0
    fi
    # echo "--> Found commit count: $COMMIT_COUNT"

    # echo "--> Performing partial clone to fetch Makefile..."
    if ! git clone --quiet --no-checkout --depth=1 --filter=blob:none -b "$BRANCH" "$REPO_URL" "$TMP_DIR"; then
        echo "Error: Failed to clone repository. This can happen with private repos or incorrect branch names." >&2
        exit 1
    fi

    cd "$TMP_DIR" || exit 1 # Exit if cd fails
    
    MAKEFILE_PATH="kernel/Makefile"
    if ! git checkout --quiet "origin/$BRANCH" -- "$MAKEFILE_PATH" > /dev/null 2>&1; then
         echo "Error: Failed to find '$MAKEFILE_PATH' on branch '$BRANCH'." >&2
         exit 1
    fi
    # echo "--> Successfully extracted '$MAKEFILE_PATH'"

    # echo "--> Parsing Makefile for version logic..."
    
    FINAL_VERSION=""
    # Attempt 1: Version based on commit count
    if [ "$COMMIT_COUNT" -gt 0 ]; then
        FORMULA_LINE=$(grep -E 'KSU_VERSION.*(KSU_GIT_VERSION|rev-list)' "$MAKEFILE_PATH" || true)
        if [ -n "$FORMULA_LINE" ]; then
            MATH_EXPR=$(echo "$FORMULA_LINE" | sed 's/.*expr //;s/)).*//' | xargs)
            if [ -n "$MATH_EXPR" ]; then
                CALC_STRING=$(echo "$MATH_EXPR" | sed -E "s/\\$\(KSU_GIT_VERSION\)|\\$\(shell.*rev-list[^\)]*\)/$COMMIT_COUNT/")
                FINAL_VERSION=$(echo "$CALC_STRING" | bc)
            fi
        fi
    fi

    # Attempt 2: Hardcoded version (fallback)
    if [ -z "$FINAL_VERSION" ]; then
        # Check for $(eval KSU_VERSION=...)
        FINAL_VERSION=$(grep -E '^\$\(eval KSU_VERSION=[0-9]+\)' "$MAKEFILE_PATH" | head -n 1 | grep -oP '[0-9]+')
        # If not found, check for ccflags-y += -DKSU_VERSION=...
        if [ -z "$FINAL_VERSION" ]; then
            FINAL_VERSION=$(grep -E '^ccflags-y \+= -DKSU_VERSION=[0-9]+' "$MAKEFILE_PATH" | head -n 1 | grep -oP '[0-9]+')
        fi
    fi

    if [ -n "$FINAL_VERSION" ]; then
	echo "$FINAL_VERSION"
        # echo
        # echo "=========================================="
        # echo "  Repository: $OWNER/$REPO ($BRANCH)"
        # echo "  KernelSU Version: $FINAL_VERSION"
        # echo "------------------------------------------"
        # if [ -n "$FORMULA_LINE" ] && [ "$COMMIT_COUNT" -gt 0 ]; then
            # echo "  Method: Calculated from Git commit count"
            # echo "  Formula: $MATH_EXPR"
            # echo "  Commit Count Used: $COMMIT_COUNT"
        # else
            # echo "  Method: Hardcoded in Makefile"
        # fi
        # echo "=========================================="
        return
    else
        echo "Error: Could not determine KSU version from the provided Makefile." >&2
        exit 1
    fi
}

main

