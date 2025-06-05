#!/bin/bash

tag="$1"
repo_dir="$2"
artifacts_dir="$3"

cd $artifacts_dir
for kernel in *; do
    if [ -d "$kernel" ]; then
       escaped_kernel=$(printf '%q' "$kernel")
       echo "Zipping $escaped_kernel..."
       zip -r "$kernel.zip" "$kernel/*"
       rm -rf "$kernel/"
       echo "Uploading $escaped_kernel.zip..."
       cd $repo_dir
       gh release upload "$tag" "$artifacts_dir/$escaped_kernel.zip"
       cd $artifacts_dir
    fi
done
