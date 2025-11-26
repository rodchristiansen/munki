# Upstream Synchronization Guide

This document tracks the differences between our internal fork (`emilycarru-its-infra/munki`) and the upstream repository (`rodchristiansen/munki`).

## Repository Overview

*   **Upstream**: `https://github.com/rodchristiansen/munki` (Branch: `main`)
*   **Internal**: `https://github.com/emilycarru-its-infra/munki` (Branch: `main`)

## Key Differences

### 1. Custom Branding
We maintain custom branding assets for Managed Software Center.
*   **Files**:
    *   `code/apps/Managed Software Center/Resources/WebResources/branding.jpg`
    *   `code/apps/Managed Software Center/Resources/WebResources/branding1.jpg`
    *   `code/apps/Managed Software Center/Resources/WebResources/branding2.jpg`
    *   `code/apps/Managed Software Center/AppIcon.icon/` (Custom icons)
    *   `code/apps/Managed Software Center/*/InfoPlist.strings` (Localized strings)

### 2. Launchd Configuration
We have customized launchd property lists for our environment.
*   **Files**:
    *   `launchd/LaunchAgents/com.googlecode.munki.ManagedSoftwareCenter.plist`
    *   `launchd/LaunchAgents/com.googlecode.munki.MunkiStatus.plist`
    *   `launchd/LaunchAgents/com.googlecode.munki.munki-notifier.plist`

### 3. Build System Customizations
We use custom build scripts for our internal deployment.
*   **Files**:
    *   `build.sh`
    *   `build.command`

### 4. Code Customizations
Our `munkiimport` tool has been enhanced with internal logic:
*   **Git Integration**: Automatic `git pull` before import.
*   **Filename Sanitization**: Enforces naming conventions (e.g., adding `-Apple` or `-Intel` suffixes).
*   **File**: `code/cli/munki/munkiimport/munkiimport.swift`

## Sync Instructions

To fetch updates from upstream and merge them into our internal fork:

1.  **Add Upstream Remote** (if not already added):
    ```bash
    git remote add origin https://github.com/rodchristiansen/munki.git
    ```

2.  **Fetch Latest Changes**:
    ```bash
    git fetch origin
    ```

3.  **Create a Merge Branch**:
    ```bash
    git checkout -b sync-upstream-$(date +%Y%m%d)
    ```

4.  **Merge Upstream Main**:
    ```bash
    git merge origin/main
    ```

5.  **Resolve Conflicts**:
    *   **Branding/Launchd**: Always keep **OUR** versions (HEAD).
    *   **Code**: Generally accept **THEIR** (upstream) versions, but **BE CAREFUL** with `munkiimport.swift`. You must manually re-apply our Git integration and sanitization logic if it gets overwritten.
    *   **Deleted Files**: If upstream deleted a file (like `Package.swift`), allow the deletion unless we specifically need it.

6.  **Verify Customizations**:
    *   Check `munkiimport.swift` for `isGitRepository` and `sanitizeInstallerFilename` functions.
    *   Check `Managed Software Center` branding images.

7.  **Push and PR**:
    Push the branch to `emilycarru` and create a Pull Request for review.

## Recent Sync History

*   **2025-11-25**: Merged `rodchristiansen/munki:main` (YAML support update).
    *   **Status**: Conflicts resolved.
    *   **Notes**: `logouthelper` (Python) was deleted in favor of Swift version. `munkiimport` customizations were preserved (or re-applied). Legacy files (`MPKconvert.swift`, `MPKcreate.swift`, `YAML_SUPPORT.md`) were cleaned up.
