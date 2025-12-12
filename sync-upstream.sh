#!/bin/bash
# sync-upstream.sh - Sync with upstream while preserving fork customizations
# 
# This script automates the upstream sync process for our Munki fork.
# It uses .gitattributes with merge=ours to automatically keep our
# customization files during merges.
#
# Usage: ./sync-upstream.sh [--dry-run]
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
    echo ""
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Munki Fork - Upstream Sync Script                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Ensure we're on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo -e "${RED}✗ Not on main branch (currently on: $CURRENT_BRANCH)${NC}"
    echo -e "  Please checkout main first: git checkout main"
    exit 1
fi

# Ensure working tree is clean
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${RED}✗ Working tree is not clean${NC}"
    echo -e "  Please commit or stash changes first"
    git status --short
    exit 1
fi

# Ensure the 'ours' merge driver is configured
if ! git config --get merge.ours.driver > /dev/null 2>&1; then
    echo -e "${YELLOW}Configuring 'ours' merge driver...${NC}"
    git config merge.ours.driver true
fi

echo -e "${GREEN}✓${NC} On main branch"
echo -e "${GREEN}✓${NC} Working tree clean"
echo -e "${GREEN}✓${NC} Merge driver configured"
echo ""

# Fetch upstream
echo -e "${BLUE}Fetching upstream...${NC}"
git fetch upstream

# Check what's new
NEW_COMMITS=$(git log --oneline HEAD..upstream/main | wc -l | tr -d ' ')
if [[ "$NEW_COMMITS" == "0" ]]; then
    echo -e "${GREEN}✓ Already up to date with upstream!${NC}"
    exit 0
fi

echo -e "${YELLOW}Found $NEW_COMMITS new commit(s) from upstream:${NC}"
git log --oneline HEAD..upstream/main
echo ""

# Show which files will change
echo -e "${BLUE}Files that will be updated:${NC}"
git diff --stat HEAD..upstream/main | tail -20
echo ""

# List protected files that will be auto-kept
echo -e "${BLUE}Protected files (will keep OURS via .gitattributes):${NC}"
echo -e "  • branding*.jpg (custom images)"
echo -e "  • */InfoPlist.strings (all locales)"
echo -e "  • project.pbxproj (Xcode project)"
echo -e "  • launchd/*.plist (custom paths)"
echo -e "  • **/customizations.md (our docs)"
echo -e "  • .github/copilot-instructions.md"
echo -e "  • CUSTOMIZATIONS.md"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN - Would merge these changes${NC}"
    exit 0
fi

# Confirm
read -p "Proceed with merge? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

# Create sync branch
SYNC_BRANCH="sync-upstream-$(date +%Y%m%d-%H%M)"
echo ""
echo -e "${BLUE}Creating sync branch: $SYNC_BRANCH${NC}"
git checkout -b "$SYNC_BRANCH"

# Merge upstream
echo -e "${BLUE}Merging upstream/main...${NC}"
if git merge upstream/main --no-edit; then
    echo -e "${GREEN}✓ Merge successful${NC}"
else
    echo -e "${RED}✗ Merge conflicts detected${NC}"
    echo -e "  Resolve conflicts, then run:"
    echo -e "    git add ."
    echo -e "    git commit"
    echo -e "    git checkout main && git merge $SYNC_BRANCH"
    exit 1
fi

# Update submodules
echo ""
echo -e "${BLUE}Updating submodules...${NC}"
git submodule update --init --recursive

# Check if any submodules have remote updates
for submodule in code/cli/munki/munkipkg code/munkiadmin; do
    if [[ -d "$submodule" ]]; then
        echo -e "  Checking $submodule..."
        pushd "$submodule" > /dev/null
        git fetch origin 2>/dev/null || true
        BEHIND=$(git log --oneline HEAD..origin/main 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$BEHIND" != "0" ]]; then
            echo -e "  ${YELLOW}$submodule is $BEHIND commit(s) behind origin/main${NC}"
            read -p "  Update to latest? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                git checkout main && git pull origin main
                echo -e "  ${GREEN}✓ Updated $submodule${NC}"
            fi
        else
            echo -e "  ${GREEN}✓ $submodule is up to date${NC}"
        fi
        popd > /dev/null
    fi
done

# Stage any submodule changes
git add code/cli/munki/munkipkg code/munkiadmin 2>/dev/null || true
if [[ -n $(git status --porcelain) ]]; then
    git commit --amend --no-edit
fi

# Merge back to main
echo ""
echo -e "${BLUE}Merging back to main...${NC}"
git checkout main
git merge "$SYNC_BRANCH" --no-edit
git branch -d "$SYNC_BRANCH"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Sync Complete!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Review changes with: ${BLUE}git log --oneline -10${NC}"
echo -e "Push with: ${BLUE}git push origin main${NC}"
echo ""

# Verify customizations preserved
echo -e "${BLUE}Verifying customizations preserved...${NC}"
BRANDING_SIZE=$(stat -f%z "code/apps/Managed Software Center/Managed Software Center/Resources/WebResources/branding.jpg" 2>/dev/null || echo "0")
if [[ "$BRANDING_SIZE" -lt 50000 ]]; then
    echo -e "${GREEN}✓${NC} Branding images preserved (${BRANDING_SIZE} bytes)"
else
    echo -e "${YELLOW}⚠${NC} Branding images may have been overwritten (${BRANDING_SIZE} bytes)"
fi
