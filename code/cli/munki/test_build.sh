#!/bin/bash
cd /Users/rod/Developer/munki/code/cli/munki
echo "Building makecatalogs..."
swift build -c release --target makecatalogs
echo "Build exit code: $?"
echo "Checking for makecatalogs binary..."
ls -la .build/arm64-apple-macosx/release/makecatalogs
echo "Build complete!"
