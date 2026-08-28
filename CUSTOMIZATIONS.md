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

---

## Trap: the CLI Xcode project drops fork-only files

`code/cli/munki/munki.xcodeproj/project.pbxproj` used to use Xcode's
**synchronized folder groups** (`PBXFileSystemSynchronizedRootGroup`), which
compile every file in a directory automatically — so fork-only sources were
picked up without being listed anywhere.

**Upstream v7.3.0 replaced that with explicit per-file references**, enumerating
only upstream's own files. Accepting upstream's `project.pbxproj` therefore
silently drops every fork-only source: the file stays on disk, git shows no
conflict, and the target simply stops compiling it. The failure surfaces later as
`cannot find '<Type>' in scope` — in the v7.3.0 sync it was
`manifestutil.swift:77: cannot find 'Convert' in scope`, because
`manifestutil/MUconvert.swift` was no longer a member of the `manifestutil`
target.

**After every upstream sync, check that no fork-only source fell out:**

```bash
cd code/cli/munki
find . -name '*.swift' -not -path './munkipkg/*' -not -path '*/.build/*' | while read -r f; do
  grep -q "$(basename "$f")" munki.xcodeproj/project.pbxproj || echo "MISSING: $f"
done
```

The same trap runs in the **opposite direction** for the app projects.

`code/apps/Managed Software Center/Managed Software Center.xcodeproj/project.pbxproj`
is a **keep OURS** file (custom app name, branding, icons). Keeping it means
*upstream's newly added source files never get referenced*, so they sit on disk
uncompiled and the app fails with `cannot find type '<Type>' in scope`. The
v7.3.0 sync added three files this way — `Controllers/HoursSelector.swift`,
`Controllers/MSCBlockingAppsController.swift`,
`Controllers/PrefsWindowController.swift`.

So after a sync, audit **both** directions:

```bash
cd code/apps
for d in */; do
  pbx=$(find "$d" -maxdepth 1 -name '*.xcodeproj')/project.pbxproj
  [ -f "$pbx" ] || continue
  find "$d" -name '*.swift' -not -path '*/build/*' | while read -r f; do
    grep -q "$(basename "$f")" "$pbx" || echo "UNREFERENCED: $f"
  done
done
```

Build all three apps too, not just the CLI — `make_swift_munki_pkg.sh` needs
Managed Software Center, MunkiStatus and munki-notifier, each at
`<app>/build/Release/`, which is why `SYMROOT="$PWD/build"` must survive.

Fork-only CLI sources that must stay in the project:

| File | Target | Provides |
|---|---|---|
| `manifestutil/MUconvert.swift` | `manifestutil` | `convert` subcommand (YAML ⇄ plist) |
| `makepkginfo/MPIconvert.swift` | `makepkginfo` | `convert` subcommand (YAML ⇄ plist) |

`yaml_to_plist/yaml_to_plist.swift` is intentionally absent from the Xcode
project — it builds via `Package.swift`, not a target here.

**Build every scheme before releasing, not a sample.** The release workflow builds
all of them; building only `managedsoftwareupdate`, `munkiimport` and
`makecatalogs` will not catch a dropped `manifestutil` file:

```bash
for s in $(xcodebuild -project munki.xcodeproj -list | sed -n '/Schemes:/,$p' | tail -n +2 | tr -d ' '); do
  xcodebuild -project munki.xcodeproj -scheme "$s" -configuration Release build >/dev/null 2>&1 || echo "FAILED: $s"
done
```

`munkiCLItesting` is a test bundle and reports `Found no destinations ... for
action build`; that one is expected and is not part of the shipped pkg.
