#!/bin/bash

for kernel in *; do
    if [ -d "$kernel" ]; then
       escaped_kernel=$(printf '%q' "$kernel")
       echo "Zipping $escaped_kernel..."
       zip -r "$escaped_kernel.zip" $kernel/
       rm -rf $kernel/
       echo "Uploading $escaped_kernel.zip..."
       gh release upload "$1" "$escaped_kernel.zip"
    fi
done
