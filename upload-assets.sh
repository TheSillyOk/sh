#!/bin/bash

tag="$1"
repo_dir="$2"
artifacts_dir="$3"

cd $repo_dir

for kernel in $artifacts_dir/*; do
    if [ -d "$kernel" ]; then
       escaped_kernel=$(printf '%q' "$kernel")
       echo "Zipping $escaped_kernel..."
       zip -r "$kernel.zip" "$kernel/"
       rm -rf "$kernel/"
       echo "Uploading $escaped_kernel.zip..."
       gh release upload "$tag" "$escaped_kernel.zip"
    fi
done
