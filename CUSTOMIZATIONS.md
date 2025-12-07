# Fork Customizations Index

**Purpose:** Index of all customizations in this fork that differ from upstream [munki/munki](https://github.com/munki/munki).

**Upstream:** `https://github.com/munki/munki` (Branch: `main`)  
**This Fork:** `emilycarru-its-infra/munki` → upstream to `rodchristiansen/munki`

---

## Quick Reference

| Category | Location | Documentation |
|----------|----------|---------------|
| **munkiimport** | `code/cli/munki/munkiimport/` | [customizations.md](code/cli/munki/munkiimport/customizations.md) |
| **Branding** | `code/apps/Managed Software Center/` | [customizations.md](code/apps/Managed%20Software%20Center/customizations.md) |
| **Launchd** | `launchd/` | [customizations.md](launchd/customizations.md) |
| **Build System** | Root + `code/tools/` | [customizations.md](code/tools/customizations.md) |
| **Versioning** | Multiple locations | [Below](#versioning-strategy) |

---

## Customization Categories

### 1. munkiimport Enhancements
**File:** `code/cli/munki/munkiimport/munkiimport.swift`  
**Documentation:** [`code/cli/munki/munkiimport/customizations.md`](code/cli/munki/munkiimport/customizations.md)

**Features (+305 lines):**
- Git pull with rebase fallback before imports
- Silent makecatalogs refresh
- Filename sanitization with `-Apple`/`-Intel` architecture suffixes
- Read-only filesystem handling
- Extended template field copying (scripts, forced_install, etc.)
- Interactive architecture editing

### 2. Branding Assets
**Location:** `code/apps/Managed Software Center/`  
**Documentation:** [`code/apps/Managed Software Center/customizations.md`](code/apps/Managed%20Software%20Center/customizations.md)

**Assets:**
- `Resources/WebResources/branding.jpg` - Header image
- `Resources/WebResources/branding1.jpg` - Alternate branding
- `Resources/WebResources/branding2.jpg` - Alternate branding
- `AppIcon.icon/` - Custom application icons
- `*/InfoPlist.strings` - Localized display names (all locales)
- `Managed Software Center.xcodeproj/project.pbxproj` - Xcode project configuration

### 3. Launchd Configuration
**Location:** `launchd/`  
**Documentation:** [`launchd/customizations.md`](launchd/customizations.md)

**Modified plists:**
- LaunchAgents for ManagedSoftwareCenter, MunkiStatus, munki-notifier
- LaunchDaemons for authrestartd, logouthelper, managedsoftwareupdate-*

### 4. Build System
**Location:** Root + `code/tools/`  
**Documentation:** [`code/tools/customizations.md`](code/tools/customizations.md)

**Custom scripts:**
- `build.sh` - Custom build script with signing/notarization
- `build.command` - Double-click build launcher
- `code/tools/make_munki_mpkg.sh` - Modified package builder
- `code/tools/make_swift_munki_pkg.sh` - Swift tools packager

---

## Versioning Strategy

### Our Approach vs Upstream

| Component | Upstream Format | Our Format | Example |
|-----------|-----------------|------------|---------|
| CLI Tools | `7.0.x` | `7.0.x` (same) | `7.0.3` |
| MSC.app | `7.0.x` | `7.0.x` (same) | `7.0.1` |
| Build Number | Sequential | Sequential | `1`, `2`, ... |

### Files to Preserve During Merges

Always keep **OUR** versions (accept HEAD) for:

```
code/apps/Managed Software Center/Managed Software Center/Info.plist
code/apps/MunkiStatus/MunkiStatus/Info.plist
code/cli/munki/shared/version.swift
```

**Current version.swift:**
```swift
let CLI_TOOLS_VERSION = "7.0.3"
let BUILD = "<BUILD_GOES_HERE>"
```

---

## Merge Workflow

When syncing from upstream:

### 1. Preview Changes
```bash
git fetch upstream
git log --oneline HEAD..upstream/main      # See new commits
git diff HEAD..upstream/main --stat        # See changed files
```

### 2. Create Merge Branch & Merge
```bash
git checkout -b sync-upstream-$(date +%Y%m%d)
git merge upstream/main
```

### 3. Handle Submodule Conflicts
Submodules (`code/munkiadmin`, `code/cli/munki/munkipkg`) often conflict:
```bash
# Update submodule to latest
cd code/munkiadmin && git fetch origin && git checkout origin/main && cd ../..

# Stage submodule updates
git add code/munkiadmin code/cli/munki/munkipkg
```

### 4. Conflict Resolution Priority

| File Type | Resolution |
|-----------|------------|
| `branding*.jpg` | Keep OURS |
| `AppIcon.icon/*` | Keep OURS |
| `*/InfoPlist.strings` | Keep OURS |
| `Managed Software Center.xcodeproj/project.pbxproj` | Keep OURS |
| `Info.plist` (version) | Keep OURS |
| `version.swift` | Keep OURS |
| `launchd/*.plist` | Keep OURS |
| `munkiimport.swift` | Accept THEIRS (our customizations are now upstream!) |
| `code/cli/*` | Accept THEIRS |
| `code/tools/*` | Accept THEIRS |
| Submodules | Update to latest origin/main |
| Everything else | Accept THEIRS |

### 5. Commit & Complete Merge
```bash
git commit -m "Merge upstream/main: <brief description>"
git checkout main
git merge sync-upstream-$(date +%Y%m%d)
git branch -d sync-upstream-$(date +%Y%m%d)  # Cleanup
```

### 6. Verify & Push
```bash
# Check munkiimport customizations preserved
grep -c "isGitRepository\|sanitizeInstallerFilename" \
  code/cli/munki/munkiimport/munkiimport.swift

# Test build
./build.sh

# Push
git push origin main
```

---

## File Inventory

### Files We Own (never accept upstream changes)
```
code/apps/Managed Software Center/Resources/WebResources/branding*.jpg
code/apps/Managed Software Center/AppIcon.icon/
code/apps/Managed Software Center/*/InfoPlist.strings
code/apps/Managed Software Center/Managed Software Center.xcodeproj/project.pbxproj
launchd/LaunchAgents/*.plist
launchd/LaunchDaemons/*.plist
build.sh
build.command
CUSTOMIZATIONS.md
.github/copilot-instructions.md
```

### Files We Enhance (merge carefully)
```
code/cli/munki/munkiimport/munkiimport.swift
code/tools/make_munki_mpkg.sh
code/tools/make_swift_munki_pkg.sh
```

### Files We Track Version Only
```
code/apps/Managed Software Center/Managed Software Center/Info.plist
code/apps/MunkiStatus/MunkiStatus/Info.plist
code/cli/munki/shared/version.swift
```

---

## See Also

- [Upstream Sync Guide](.github/copilot-instructions.md) - Detailed sync history
- [munkiimport Customizations](code/cli/munki/munkiimport/customizations.md) - Full feature documentation
- [Official Munki Wiki](https://github.com/munki/munki/wiki)
