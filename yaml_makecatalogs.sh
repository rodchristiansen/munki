#!/bin/bash

# YAML-enabled makecatalogs workflow
# This script converts YAML pkgsinfo files to plist, runs makecatalogs, then optionally converts back

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

REPO_PATH="${1:-/Users/rod/Developer/munki/test_yaml_repo}"
YAML_TO_PLIST="/Users/rod/Developer/munki/code/cli/munki/.build/arm64-apple-macosx/release/yaml_to_plist"

echo -e "${GREEN}YAML-Enabled Makecatalogs Workflow${NC}"
echo "Repository: $REPO_PATH"
echo

# Check if yaml_to_plist tool exists
if [ ! -x "$YAML_TO_PLIST" ]; then
    echo -e "${RED}Error: yaml_to_plist tool not found at $YAML_TO_PLIST${NC}"
    exit 1
fi

# Create temp directory for converted files
TEMP_DIR=$(mktemp -d)
echo -e "${YELLOW}Using temporary directory: $TEMP_DIR${NC}"

# Copy repo structure to temp directory
if [ -d "$REPO_PATH" ]; then
    cp -r "$REPO_PATH" "$TEMP_DIR/repo"
else
    echo -e "${RED}Error: Repository path $REPO_PATH not found${NC}"
    exit 1
fi

TEMP_REPO="$TEMP_DIR/repo"

# Find and convert YAML files to plist
echo -e "${YELLOW}Converting YAML pkgsinfo files to plist...${NC}"
yaml_count=0
converted_count=0

while IFS= read -r -d '' yaml_file; do
    yaml_count=$((yaml_count + 1))
    
    # Get relative path and create plist filename
    rel_path="${yaml_file#$TEMP_REPO/}"
    plist_file="${yaml_file%.yaml}.plist"
    
    echo "Converting: $rel_path"
    
    # Convert YAML to plist
    if "$YAML_TO_PLIST" "$yaml_file" > "$plist_file"; then
        converted_count=$((converted_count + 1))
        # Remove the YAML file so makecatalogs only sees plist
        rm "$yaml_file"
    else
        echo -e "${RED}Failed to convert: $rel_path${NC}"
    fi
done < <(find "$TEMP_REPO" -name "*.yaml" -type f -print0)

echo -e "${GREEN}Converted $converted_count of $yaml_count YAML files${NC}"
echo

# Run makecatalogs on the converted repository
echo -e "${YELLOW}Running makecatalogs on converted repository...${NC}"
if /usr/local/munki/makecatalogs "$TEMP_REPO"; then
    echo -e "${GREEN}makecatalogs completed successfully!${NC}"
    echo
    
    # Show generated catalogs
    echo -e "${YELLOW}Generated catalogs:${NC}"
    if [ -d "$TEMP_REPO/catalogs" ]; then
        ls -la "$TEMP_REPO/catalogs"
        echo
        
        # Copy catalogs back to original repo
        if [ -d "$REPO_PATH/catalogs" ]; then
            echo -e "${YELLOW}Copying catalogs back to original repository...${NC}"
            cp -r "$TEMP_REPO/catalogs/"* "$REPO_PATH/catalogs/"
            echo -e "${GREEN}Catalogs copied to $REPO_PATH/catalogs/${NC}"
        fi
    else
        echo -e "${YELLOW}No catalogs directory found${NC}"
    fi
else
    echo -e "${RED}makecatalogs failed${NC}"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"
echo -e "${GREEN}Workflow completed successfully!${NC}"
