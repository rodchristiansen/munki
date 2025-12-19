````instructions
# GitHub Copilot Memory - Munki YAML Support Project

## CRITICAL: Mac VS Code Terminal Limitations

**NEVER** use `cat` with heredocs (`<< 'EOF'`) or output large scripts directly in the VS Code integrated terminal on macOS. This breaks the terminal and stops agent runs. Instead:
- Write scripts to files using the `create_file` tool, then execute them
- Use the `replace_string_in_file` or `edit` tools for file modifications
- For small outputs, use `echo` with simple strings only

## Project Overview
**Repository**: rodchristiansen/munki (fork of munki/munki)  
**Branch**: add-yaml-support  
**Goal**: Build and install YAML-capable Munki admin tools to replace Python-based tools that only support plist format  
**User**: Rod Christiansen  
**Last Updated**: December 5, 2025

## Fork Customization Documentation

All fork customizations are documented alongside the customized code:

| Category | Documentation |
|----------|---------------|
| **Master Index** | [`CUSTOMIZATIONS.md`](../CUSTOMIZATIONS.md) |
| **munkiimport** | [`code/cli/munki/munkiimport/customizations.md`](../code/cli/munki/munkiimport/customizations.md) |
| **Branding** | [`code/apps/Managed Software Center/customizations.md`](../code/apps/Managed%20Software%20Center/customizations.md) |
| **Launchd** | [`launchd/customizations.md`](../launchd/customizations.md) |
| **Build System** | [`code/tools/customizations.md`](../code/tools/customizations.md) |  

## Problem Statement
- User has YAML pkgsinfo files that can't be processed by standard Munki 6.x/7.x
- Standard Munki's `makecatalogs`, `munkiimport`, etc. only understand plist format via FoundationPlist.py
- User needs YAML-capable versions of admin tools to process their modern YAML workflow

## COMPLETED WORK - MunkiAdmin YAML Support

### MunkiAdmin GUI Application
**Status**: SUCCESSFULLY COMPLETED  
**Application Location**: `/Users/rod/Desktop/MunkiAdmin-YAML-Enhanced.app`  
**Implementation**: Full YAML support with Python bridge approach  

### MunkiAdmin Features Implemented
- **File Detection**: Automatic YAML file detection by extension (.yaml/.yml)
- **Dual-Format I/O**: Seamless handling of both plist and YAML files
- **Backward Compatibility**: All existing plist workflows remain unchanged
- **Python Bridge**: Real YAML parsing using PyYAML library
- **Repository Manager**: Enhanced with YAML reading/writing methods
- **Testing Complete**: Verified with sample_firefox.yaml and sample_dev_manifest.yaml

### MunkiAdmin Technical Implementation
- **Repository Manager** (`MAMunkiRepositoryManager.m`): Enhanced with YAML detection and I/O
- **Python Bridge** (`yaml_bridge.py`): Multi-format conversion utility
- **Build System**: CocoaPods integration successful
- **Error Handling**: Graceful fallback to plist if YAML parsing fails
- **Python Bridge**: Uses system Python 3 with PyYAML for YAML parsing
- **MunkiAdmin**: Reads and displays YAML files correctly

## Technical Context

### Munki Architecture Understanding
**Purpose**: macOS software management system for enterprise deployment
**Components**:
- Repository structure: `pkgs/`, `pkgsinfo/`, `catalogs/`, `manifests/`
- Admin tools: `makecatalogs`, `munkiimport`, `makepkginfo`, `manifestutil`, `repoclean`
- Client tools: `managedsoftwareupdate`, Managed Software Center.app
- Workflow: pkgsinfo files → makecatalogs → catalogs → client deployment

### Current Repository Structure
```
/Users/rod/Developer/munki/
├── code/cli/munki/           # Swift Package Manager project
│   ├── Package.swift         # YAML-enabled tools definition
│   ├── .build/arm64-apple-macosx/release/
│   │   ├── yaml_migrate      # Built successfully (2.7MB)
│   │   └── yaml_to_plist     # Built successfully (1.2MB)
├── test_conversion/pkgsinfo/ # YAML pkgsinfo files (converted)
├── test_yaml_repo/           # Test repository for YAML workflow
├── yaml_makecatalogs.sh      # YAML workflow script created
└── munkiadmin/               # MunkiAdmin GUI with YAML support COMPLETE
```

### Package.swift Configuration
**Dependencies**:
- Yams 6.0.2+ (YAML parsing library)
- swift-argument-parser 1.2.0+

**Target Structure**:
- MunkiShared library (shared utilities)
- Executables: makecatalogs, munkiimport, manifestutil, repoclean
- Working tools: yaml_migrate, yaml_to_plist

### Build Status
**Successfully Built**:
- `yaml_migrate` (2.7MB) - Converts between YAML/plist formats
- `yaml_to_plist` (1.2MB) - YAML to plist converter
- **MunkiAdmin-YAML-Enhanced.app** - Full GUI application with YAML support

**Build Failures**:
- `makecatalogs` - Missing MunkiShared library symbols
- `munkiimport` - Missing MunkiShared library symbols  
- `manifestutil` - Missing MunkiShared library symbols
- `repoclean` - Missing MunkiShared library symbols

**Root Cause**: Swift compilation order issues with MunkiShared library symbol resolution

## YAML Workflow Solutions

### Working Solutions Available
1. **MunkiAdmin GUI**: COMPLETE - Full YAML support at `/Users/rod/Desktop/MunkiAdmin-YAML-Enhanced.app`
2. **YAML Conversion Tools**: WORKING - `yaml_migrate` and `yaml_to_plist` functional
3. **Hybrid Workflow Script**: CREATED - `yaml_makecatalogs.sh` for automated conversion

### Hybrid makecatalogs Workflow
- **Script**: `/Users/rod/Developer/munki/yaml_makecatalogs.sh`
- **Process**: YAML → convert to plist → run Python makecatalogs → generate catalogs
- **Benefits**: Use existing Python tools while maintaining YAML workflow
- **Status**: Ready for testing

## Previous Work Done

### YAML Conversion Success
- Converted 19 plist pkgsinfo files to YAML format using built tools
- YAML files validate and convert back to plist correctly
- Conversion process working perfectly with `yaml_migrate`

### Build Attempts
- Multiple `swift build -c release` attempts
- Partial success with yaml tools, failures with main admin tools
- Swift Package Manager resolving dependencies correctly
- ARM64 architecture building successfully

### Testing Performed
- `yaml_to_plist` tool functional and processing YAML correctly
- YAML format validation successful  
- Conversion round-trip testing successful
- **BREAKTHROUGH**: yaml_to_plist successfully converted sample_firefox.yaml to perfect plist format
- YAML support fully implemented and working in built tools
- **MunkiAdmin**: Full GUI testing complete with YAML files

### Sample YAML Files Working
- `sample_firefox.yaml` - Complete package metadata
- `sample_dev_manifest.yaml` - Manifest configuration

## Current Status
**Last Session Date**: August 31, 2025  
**Working Directory**: `/Users/rod/Developer/munki/code/cli/munki`  
**Build Status**: Xcode build in progress (very slow), SPM partial success  
**Immediate Solution**: Use hybrid workflow with working YAML tools  

### Available Working Solutions
1. **MunkiAdmin GUI**: Complete at `/Users/rod/Desktop/MunkiAdmin-YAML-Enhanced.app`
2. **YAML Conversion Tools**: `yaml_migrate`, `yaml_to_plist` fully functional
3. **Hybrid Workflow**: `yaml_makecatalogs.sh` ready for testing
4. **Swift CLI Build**: Xcode build in progress but very slow

## Next Actions Available
1. **Use MunkiAdmin**: READY - Launch `/Users/rod/Desktop/MunkiAdmin-YAML-Enhanced.app`
2. **Test Hybrid Workflow**: Run `yaml_makecatalogs.sh` script with test repository
3. **Continue Swift Build**: Resolve MunkiShared library symbol resolution
4. **Deploy YAML Workflow**: Use working tools in production environment

## Key Files to Monitor
- `/Users/rod/Desktop/MunkiAdmin-YAML-Enhanced.app` - COMPLETE GUI application
- `/Users/rod/Developer/munki/yaml_makecatalogs.sh` - Hybrid workflow script
- `/Users/rod/Developer/munki/code/cli/munki/Package.swift` - Build configuration
- `/Users/rod/Developer/munki/test_yaml_repo/` - Test repository structure
- Build output in `.build/arm64-apple-macosx/release/` directory

## Technical Notes
- macOS environment with zsh shell
- Swift Package Manager as build system
- ARM64 architecture (Apple Silicon)
- YAML library: Yams (maintained Swift YAML parser)
- Target: Replace `/usr/local/munki/` admin tools with YAML-capable versions
- **Python Bridge**: Uses system Python 3 with PyYAML for YAML parsing
- **CocoaPods**: Used for MunkiAdmin dependencies

## Repository Context
- Fork of official munki/munki repository
- Branch: add-yaml-support contains YAML support being contributed to upstream via PR
- Branch: main contains fork customizations plus PR code
- This is production environment where YAML workflow is preferred
- **.git/info/exclude**: Updated to exclude COPILOT_MEMORY.md from commits

## Documentation Structure

### Fork Customizations (Will NOT go upstream)
See [CUSTOMIZATIONS.md](/CUSTOMIZATIONS.md) for full index:
- munkiimport.swift enhancements (git pull, filename sanitization)
- build.sh custom wrapper
- Custom app icon
- Version file differences

### PR Contributions (Will go upstream)
See [code/cli/munki/YAML_PR.md](code/cli/munki/YAML_PR.md):
- YAML support in CLI tools (yamlutils.swift)
- makepkginfo convert subcommand
- manifestutil convert subcommand
- Branch: add-yaml-support (keep clean for PR)

MunkiAdmin YAML support is also a PR contribution (separate repo, branch: add-yaml-support)

## Ecosystem Integration

### MWA2 Compatibility
- MWA2 already has YAML support implemented
- Integration tested and working
- Cross-tool compatibility verified

### CLI Tools Status
- **Working**: yaml_migrate, yaml_to_plist
- **Pending**: makecatalogs, munkiimport, manifestutil, repoclean
- **Workaround**: Hybrid script approach available

## Important Reminders
- Always reference this file to maintain context across all sessions
- User prefers YAML format over plist for pkgsinfo files
- Working Swift tools prove YAML support is implemented and functional
- MunkiAdmin GUI with YAML support is COMPLETE and ready for use
- Focus is on completing build process or using hybrid workflow approach
- User is experienced with Munki and macOS development workflows
- This memory file is excluded from git commits via .git/info/exclude

## Success Metrics
- YAML files can be read and parsed correctly
- YAML files can be converted to plist format
- MunkiAdmin can handle YAML files seamlessly
- Existing plist workflows remain unaffected
- Native Swift makecatalogs with YAML support (pending/workaround available)
- End-to-end YAML workflow functional (via hybrid approach)

# Upstream Synchronization Guide

This document tracks the differences between our internal fork (`emilycarru-its-infra/munki`) and the upstream repository (`rodchristiansen/munki`).

## Repository Overview

*   **Upstream**: `https://github.com/rodchristiansen/munki` (Branch: `main`)
*   **Internal**: `https://github.com/emilycarru-its-infra/munki` (Branch: `main`)

## Key Differences

### 1. Custom Branding
We maintain custom branding assets for Managed Software Center.
*   **Files**:
    *   `code/apps/Managed Software Center/AppIcon.icon/` (Custom icons)
    *   `code/apps/Managed Software Center/*/InfoPlist.strings` (Localized strings - ALL locales)
    *   `code/apps/Managed Software Center/Managed Software Center.xcodeproj/project.pbxproj` (Xcode project)

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

### 5. Recurring Version Conflicts
These files often conflict due to version number differences (Upstream uses semantic versioning e.g. `7.0.x`, we use date-based e.g. `2025.10.13`).
*   **Files**:
    *   `code/apps/Managed Software Center/Managed Software Center/Info.plist`
    *   `code/apps/MunkiStatus/MunkiStatus/Info.plist`
    *   `code/cli/munki/shared/version.swift`
*   **Resolution**: Always keep **OUR** versions (HEAD).


## Important Rules

- **NEVER** open interactive editors like `vim`, `nano`, or `vi` in terminal commands
- **NEVER** use commands that require interactive input (use `-m` flag for commits, `--no-edit` for merges, etc.)
- Always use non-interactive alternatives or flags

## Sync Instructions

To fetch updates from upstream and merge them into our internal fork:

1.  **Add Upstream Remote** (if not already added):
    ```bash
    git remote add upstream https://github.com/rodchristiansen/munki.git
    ```

2.  **Fetch Latest Changes**:
    ```bash
    git fetch upstream
    ```

3.  **Preview What's Coming** (optional but recommended):
    ```bash
    # See new commits
    git log --oneline HEAD..upstream/main
    
    # See which files changed
    git diff HEAD..upstream/main --stat
    ```

4.  **Create a Merge Branch**:
    ```bash
    git checkout -b sync-upstream-$(date +%Y%m%d)
    ```

5.  **Merge Upstream Main**:
    ```bash
    git merge upstream/main
    ```

6.  **Handle Submodule Conflicts** (if any):
    Submodules like `code/munkiadmin` and `code/cli/munki/munkipkg` may conflict.
    ```bash
    # Update submodule to latest
    cd code/munkiadmin
    git fetch origin && git checkout origin/main
    cd ../..  # Return to repo root
    
    # Stage the submodule update
    git add code/munkiadmin code/cli/munki/munkipkg
    ```

7.  **Resolve File Conflicts**:
    *   **Branding/Launchd**: Always keep **OUR** versions (HEAD).
    *   **InfoPlist.strings**: Keep **OUR** versions for ALL locales.
    *   **project.pbxproj**: Keep **OUR** version.
    *   **Version Files**: Always keep **OUR** versions (HEAD) for `Info.plist` files and `version.swift`.
    *   **Documentation**: Keep **OUR** versions of `CUSTOMIZATIONS.md` and `.github/copilot-instructions.md`.
    *   **Code (`code/cli/*`)**: Generally accept **THEIR** versions. Our `munkiimport.swift` customizations are now upstream!
    *   **Deleted Files**: Allow deletion unless we specifically need them.

8.  **Commit the Merge**:
    ```bash
    git commit -m "Merge upstream/main: <brief description of changes>"
    ```

9.  **Merge Back to Main**:
    ```bash
    git checkout main
    git merge sync-upstream-$(date +%Y%m%d)
    git branch -d sync-upstream-$(date +%Y%m%d)  # Cleanup
    ```

10. **Verify & Push**:
    ```bash
    # Verify customizations preserved
    grep -c "isGitRepository\|sanitizeInstallerFilename" code/cli/munki/munkiimport/munkiimport.swift
    
    # Test build
    ./build.sh
    
    # Push to origin
    git push origin main
    ```

## Recent Sync History

*   **2025-12-07**: Merged `rodchristiansen/munki:main`.
    *   **Status**: Clean merge, no code conflicts.
    *   **Commits merged**: 
        - `d1c8756b`: munkiimport: Auto-detect architecture from installer filename
        - `ac4e46d3`: fix: Improve file renaming logic to handle case-insensitive filesystems
    *   **Submodules updated**: `code/munkiadmin`, `code/cli/munki/munkipkg`
    *   **New features**: Architecture auto-detection from filename patterns (x64, intel, arm64, etc.)

*   **2025-11-25**: Merged `rodchristiansen/munki:main` (YAML support update).
    *   **Status**: Conflicts resolved.
    *   **Notes**: `logouthelper` (Python) was deleted in favor of Swift version. `munkiimport` customizations were preserved (or re-applied). Legacy files (`MPKconvert.swift`, `MPKcreate.swift`, `YAML_SUPPORT.md`) were cleaned up.

*   **2025-06-26**: Merged `rodchristiansen/munki:main`.
    *   **Status**: Conflicts resolved.
    *   **Files kept OURS**: CUSTOMIZATIONS.md, all branding*.jpg, all */InfoPlist.strings (14 locales), project.pbxproj, all launchd plists.
    *   **Files accepted THEIRS**: code/cli/* (Swift CLI tools), code/tools/*, build.sh, YAML_PR.md (new file).