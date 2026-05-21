#!/bin/bash
set -e

for cmd in git curl jq sed grep bc; do
  if ! command -v "$cmd" &> /dev/null; then
      echo "Error: Required command '$cmd' is not installed. Please install it to continue." >&2
      exit 1
  fi
done

if [[ "$#" -lt 2 || "$#" -gt 4 ]]; then
  echo "Usage: $0 <owner> <repo> [branch/commit/tag]" >&2
  echo "Example: $0 tiann KernelSU main" >&2
  exit 1
fi

OWNER="$1"
REPO="$2"
REF="$3"
API_URL="https://api.github.com/repos/$OWNER/$REPO"
REPO_URL="https://github.com/$OWNER/$REPO.git"
if [[ -n "$4" ]]; then
  DEBUG=true
elif [[ "$3" == "_debug" ]]; then
  DEBUG=true
  REF=""
else
  DEBUG=false
fi
FORMULA_FILES="Kbuild Makefile"

dlog() {
  if [[ $DEBUG == true ]]; then
    echo "$1"
  fi
}
dclear() {
  if [[ $DEBUG == false ]]; then
    rm "$1"
  fi
}

main() {
  HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" "$API_URL")
  if [ "$HTTP_CODE" -ne 200 ]; then
    echo "Error: Repository not found or is private (HTTP Status: $HTTP_CODE)."
    echo "Please check for typos in the owner ('$OWNER') and repo ('$REPO') names."
    echo "This could also mean you are being rate limited by GitHub."
    exit 1
  fi

  if [ -z "$REF" ]; then
    DEFAULT_BRANCH=$(curl --silent -H "Accept: application/vnd.github.v3+json" "$API_URL" | jq -r .default_branch)
    if [[ "$DEFAULT_BRANCH" == "null" || -z "$DEFAULT_BRANCH" ]]; then
      echo "Error: Could not determine default branch." >&2
      exit 1
    fi
    REF="$DEFAULT_BRANCH"
  fi
  dlog "REF: $REF"

  if ! curl -s -f -H "Accept: application/vnd.github.v3+json" \
  "${API_URL}/commits/${REF}" > /dev/null 2>&1; then
    echo "Error: could not find ref"
    exit 1
  fi

  COMMIT_COUNT=$(curl --silent -I -H "Accept: application/vnd.github.v3+json" "$API_URL/commits?sha=$REF&per_page=1" | grep -i "^link:" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p')
  if [ -z "$COMMIT_COUNT" ]; then
    COMMIT_COUNT=$(curl --silent -H "Accept: application/vnd.github.v3+json" "$API_URL/commits?sha=$REF&per_page=100" | jq '. | length')
  fi

  if ! [[ "$COMMIT_COUNT" =~ ^[0-9]+$ && "$COMMIT_COUNT" -gt 20 ]]; then
    echo "Error: commit count looks abnormal ($COMMIT_COUNT)."
    exit 1
  fi
  dlog "COMMIT_COUNT: $COMMIT_COUNT"

  for file in $FORMULA_FILES; do
    curl -LSs "https://github.com/$OWNER/$REPO/raw/${REF}/kernel/$file" > $file
    if [[ -n $(grep "DOCTYPE html" "${file}") ]]; then
      dlog "html returned, skipping ${file}"
      dclear "$file"
      continue
    fi

    if [[ -z $(grep "KSU_VERSION" "${file}") ]]; then
      dclear "$file"
      dlog "Formula not in ${file}"
    else
      FORMULA_FILE="$file"
      dlog "FORMULA_FILE: $FORMULA_FILE"
      break
    fi
  done

  if [[ -z "$FORMULA_FILE" ]]; then
    dlog "Failed to obtain file"
    exit 1
  fi

  IFS=$'\n'
  for line in $(grep -E '.*=[0-9 ]+$' "$FORMULA_FILE" | grep -v -E "cflags|obj"); do
    VAR_NAME=$(echo "${line}" | sed -E 's/([aA-zZ_]+)[^aA-zZ_=]*?=.*/\1/')
    VAR_VALUE=$(echo "${line}" | sed -E 's/[^=]+= *([0-9]+)$/\1/')

    dlog "${VAR_NAME} -> ${VAR_VALUE}"

    sed -i -E "s/[\$\(]{2}${VAR_NAME}(\){1,2},[^\)]*)?\)/${VAR_VALUE}/g" "$FORMULA_FILE"
  done

  FORMULA_LINE=$(grep -E 'KSU_VERSION *:?=.*?(KSU.+_VERSION|rev-list|expr)' "$FORMULA_FILE" || true)
  dlog "FORMULA_LINE: $FORMULA_LINE"

  for formula in $FORMULA_LINE; do
    MATH_EXPR=$(echo "${formula}" | sed 's/.*expr //;s/))//' | xargs || continue)
    dlog "MATH_EXPR: $MATH_EXPR"

    if [ -n "$MATH_EXPR" ]; then
      CALC_STRING=$(echo "$MATH_EXPR" | sed -E "s/\\$\((KSU_GIT_VERSION|KSU_GITHUB_VERSION_COMMIT|KSU_LOCAL_VERSION|KSU.*VERSION|LOCAL_COUNT)\)|\\$\(shell.*rev-list[^\)]*\)/$COMMIT_COUNT/g;s/\)//;s/\(//" || continue)
      dlog "CALC_STRING: $CALC_STRING"

      FINAL_VERSION=$(echo "$CALC_STRING" | sed 's/[^ ]*[^0-9\+-\* ][^ ]*//g' | bc || continue)
      dlog "FINAL_VERSION: $FINAL_VERSION"
      break
    fi
  done

  if [[ -z "$FINAL_VERSION" ]]; then
    FINAL_VERSION=$(grep -E 'KSU_VERSION=[0-9]+' "$FORMULA_FILE" | head -n 1 | grep -oP '[0-9]+' || true)
    dlog "FINAL_VERSION (hardcoded): $FINAL_VERSION"
  fi
  dclear "$FORMULA_FILE"

  if [ -n "$FINAL_VERSION" ]; then
    echo "$FINAL_VERSION"
    return
  else
    echo "Error: Could not determine KSU version"
    exit 1
  fi
}

main

