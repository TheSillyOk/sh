#!/bin/bash

_extract_dksu_version_from_local_repo() {
    local makefile_path_in_repo="$1"
    local src_arg_for_make="$2"
    
    local srctree_arg_for_make="."
    local temp_makefile_name="temp_makefile_for_dksu_extraction_$$_${RANDOM}.mk"

    if [ ! -f "$makefile_path_in_repo" ]; then
        echo "Error: Makefile not found at '$PWD/$makefile_path_in_repo'" >&2
        return 1
    fi

    cat "$makefile_path_in_repo" > "$temp_makefile_name"
    echo "" >> "$temp_makefile_name"
    echo "__get_dksu_version__:" >> "$temp_makefile_name"
    echo '	@echo "EXTRACTED_DKSU_VERSION:$(lastword $(subst -DKSU_VERSION=,,$(filter -DKSU_VERSION%,$(ccflags-y))))"' >> "$temp_makefile_name"

    local make_output
    make_output=$(command make -s -f "$temp_makefile_name" "__get_dksu_version__" "srctree=${srctree_arg_for_make}" "src=${src_arg_for_make}" 2>/dev/null)
    
    rm -f "$temp_makefile_name"

    local version
    version=$(echo "$make_output" | sed -n 's/^EXTRACTED_DKSU_VERSION:\([0-9]\+\)$/\1/p' | tail -n1)

    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    else
        local info_output
        info_output=$(command make -s -f "$makefile_path_in_repo" "srctree=${srctree_arg_for_make}" "src=${src_arg_for_make}" 2>&1)
        version=$(echo "$info_output" | awk '/^-- KernelSU.* version: [0-9]+/ {match($0, /[0-9]+/); print substr($0, RSTART, RLENGTH); exit}' | tail -n1)

        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi

        if echo "$info_output" | grep -q "KSU_GIT_VERSION not defined!"; then
             if grep -qE 'ccflags-y\s*\+=\s*-DKSU_VERSION=16' "$makefile_path_in_repo"; then
                is_16_in_else_block=$(awk '/else/,/endif/{ if (/ccflags-y\s*\+=\s*-DKSU_VERSION=16/) print "16"}' "$makefile_path_in_repo" | head -n1)
                if [[ "$is_16_in_else_block" == "16" ]]; then
                     echo "16"
                     return 0
                fi
             fi
        fi
        echo "DKSU_VERSION not found." >&2
        return 1
    fi
}

extract_dksu_version_from_repo() {
    local repo_url="$1"
    local makefile_path_in_repo="$2"
    local src_dir_in_repo="$3"
    local branch_name="$4"

    if ! command -v git &> /dev/null; then
        echo "Error: git command not found. Please install git." >&2
        return 1
    fi
    
    if [ -z "$repo_url" ] || [ -z "$makefile_path_in_repo" ] || [ -z "$src_dir_in_repo" ]; then
        echo "Usage: extract_dksu_version_from_repo <repo_url> <path_to_makefile_in_repo> <src_directory_in_repo> [branch_name]" >&2
        echo "Example: $0 https://github.com/tiann/KernelSU.git kernel/Makefile kernel main" >&2
        return 1
    fi

    local temp_repo_dir
    temp_repo_dir=$(mktemp -d "temp_ksu_repo_XXXXXX")
    temp_repo_dir="$PWD/$temp_repo_dir"
    if [ ! -d "$temp_repo_dir" ]; then
        echo "Error: Could not create temporary directory" >&2
        return 1
    fi

    _cleanup_temp_dir() {
        if [ -d "$temp_repo_dir" ]; then
            echo "Cleaning up temporary directory '$temp_repo_dir'..." >&2
            rm -rf "$temp_repo_dir"
        fi
    }
    trap _cleanup_temp_dir EXIT SIGINT SIGTERM
    local current_dir="$PWD"
    cd "$temp_repo_dir"
    # echo "Attempting to clone repository '$repo_url' into '$temp_repo_dir'..." >&2
    
    local git_clone_cmd="git clone --depth 1"
    if [ -n "$branch_name" ]; then
        git_clone_cmd+=" --branch "$branch_name" --single-branch"
    fi
    git_clone_cmd+=" "$repo_url" "KSU" > "git_clone.log" 2>&1"

    if ! eval "$git_clone_cmd"; then
        echo "Error: Failed to clone repository '$repo_url'." >&2
        echo "Git clone output:" >&2
        cat "git_clone.log" >&2
        return 1
    fi
    # echo "Repository cloned successfully into '$temp_repo_dir'." >&2
    cd "$current_dir"
    
    if ! cd "$temp_repo_dir"; then
        echo "Error: Could not cd into '$temp_repo_dir'" >&2
        return 1
    fi

    local version
    version=$(_extract_dksu_version_from_local_repo "KSU/$makefile_path_in_repo" "KSU/$src_dir_in_repo")
    rm -rf $temp_repo_dir
    local exit_code=$?
    cd "$current_dir" || echo "Warning: Could not cd back to '$current_dir'. Current path: $(pwd)" >&2
    
    if [ $exit_code -eq 0 ]; then
        echo "$version"
        return 0
    else
        return $exit_code
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
        echo "Usage: $0 <repo_url> <path_to_makefile_in_repo> <src_directory_in_repo> [branch_name]" >&2
        echo "Example: $0 https://github.com/tiann/KernelSU.git kernel/Makefile kernel" >&2
        echo "Example with branch: $0 https://github.com/tiann/KernelSU.git kernel/Makefile kernel main" >&2
        exit 1
    fi

    repo_url_arg="$1"
    makefile_path_arg="$2"
    src_dir_arg="$3"
    branch_name_arg="$4"

    extract_dksu_version_from_repo "$repo_url_arg" "$makefile_path_arg" "$src_dir_arg" "$branch_name_arg"
    exit $?
fi

