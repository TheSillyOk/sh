#!/bin/bash
set -e

for cmd in git curl jq sed grep bc; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' is not installed. Please install it to continue." >&2
        exit 1
    fi
done

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    echo "Usage: $0 <owner> <repo> [branch]" >&2
    echo "Example: $0 tiann KernelSU main" >&2
    exit 1
fi

OWNER="$1"
REPO="$2"
BRANCH="$3"
API_URL="https://api.github.com"
REPO_URL="https://github.com/$OWNER/$REPO.git"

main() {

    HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" "$API_URL/repos/$OWNER/$REPO")
    if [[ "$HTTP_CODE" -ne 200 ]]; then
        echo "Error: Repository not found or is private (HTTP Status: $HTTP_CODE)." >&2
        echo "Please check for typos in the owner ('$OWNER') and repo ('$REPO') names." >&2
        exit 1
    fi

    if [ -z "$BRANCH" ]; then
        DEFAULT_BRANCH=$(curl --silent -H "Accept: application/vnd.github.v3+json" "$API_URL/repos/$OWNER/$REPO" | jq -r .default_branch)
	if [[ "$DEFAULT_BRANCH" == "null" || -z "$DEFAULT_BRANCH" ]]; then
            echo "Error: Could not determine default branch." >&2
            exit 1
	fi
        BRANCH="$DEFAULT_BRANCH"
    fi

    COMMIT_COUNT=$(curl --silent -I -H "Accept: application/vnd.github.v3+json" "$API_URL/repos/$OWNER/$REPO/commits?sha=$BRANCH&per_page=1" | grep -i "^link:" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p')
    if [ -z "$COMMIT_COUNT" ]; then
        COMMIT_COUNT=$(curl --silent -H "Accept: application/vnd.github.v3+json" "$API_URL/repos/$OWNER/$REPO/commits?sha=$BRANCH&per_page=100" | jq '. | length')
    fi

    if ! [[ "$COMMIT_COUNT" =~ ^[0-9]+$ && "$COMMIT_COUNT" -gt 20 ]]; then
        echo "Error: commit count looks abnormal ($COMMIT_COUNT)."
    fi

    curl -LSs "https://github.com/$OWNER/$REPO/raw/refs/heads/$BRANCH/kernel/Makefile" > Makefile
    test Makefile || echo "Error: failed to obtain kernel/Makefile."
    FINAL_VERSION=""
    FORMULA_LINE=$(grep -E 'KSU_VERSION *:?=.*?(KSU_GIT[^_]*_VERSION|rev-list)' "Makefile" || true)
    # echo "1: $FORMULA_LINE"
    if [[ "$FORMULA_LINE" == *"KSU"* ]]; then
      # echo "1.1: inside if"
      MATH_EXPR=$(echo "$FORMULA_LINE" | sed 's/.*expr //;s/))//' | xargs)
      # echo "2: $FORMULA_LINE"
      if [ -n "$MATH_EXPR" ]; then
        CALC_STRING=$(echo "$MATH_EXPR" | sed -E "s/\\$\((KSU_GIT_VERSION|KSU_GITHUB_VERSION_COMMIT)\)|\\$\(shell.*rev-list[^\)]*\)/$COMMIT_COUNT/;s/\)//;s/\(//")
	# echo "3: $CALC_STRING"
        FINAL_VERSION=$(echo "$CALC_STRING" | bc)
	# echo "4: $FINAL_VERSION"
      fi
    fi
    if [[ -z "$FINAL_VERSION" ]]; then
      FINAL_VERSION=$(grep -E '^\$\(eval KSU_VERSION=[0-9]+\)' "Makefile" | head -n 1 | grep -oP '[0-9]+' || true)
      # echo "5: $FINAL_VERSION"
      if [ -z "$FINAL_VERSION" ]; then
        FINAL_VERSION=$(grep -E '^ccflags-y \+= -DKSU_VERSION=[0-9]+' "Makefile" | head -n 1 | grep -oP '[0-9]+' || true)
	# echo "6: $FINAL_VERSION"
      fi
    fi
    rm Makefile

    if [ -n "$FINAL_VERSION" ]; then
      echo "$FINAL_VERSION"
      return
    else
      echo "Error: Could not determine KSU version." >&2
      exit 1
    fi
}

main

