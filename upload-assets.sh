#!/bin/bash
cd ..
git clone https://github.com/TheSillyOk/kernel_laurel_sprout_workflows --depth=1 --branch "$1" repo
cd repo
for kernel in ../downloaded-artifacts/*; do
    if [ -d "$kernel" ]; then
       escaped_kernel=$(printf '%q' "$kernel")
       echo "Zipping $escaped_kernel..."
       zip -r "../downloaded-artifacts/$kernel.zip" "../downloaded-artifacts/$kernel/"
       rm -rf "../downloaded-artifacts/$kernel/"
       echo "Uploading $escaped_kernel.zip..."
       gh release upload "$1" "../downloaded-artifacts/$escaped_kernel.zip"
    fi
done
