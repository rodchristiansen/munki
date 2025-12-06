# Fork Customizations Index

This document indexes all customizations in this fork that differ from the official [munki/munki](https://github.com/munki/munki) upstream repository.

**Upstream Repository**: https://github.com/munki/munki  
**Upstream Branch**: `main`  
**This Fork**: https://github.com/rodchristiansen/munki

---

## Important: Customizations vs PR Contributions

This fork contains TWO types of changes:

### 1. Fork-Specific Customizations (This Document)

Local customizations that will NOT go upstream. These are maintained indefinitely and preserved during upstream merges.

### 2. PR Contributions (Separate Branches)

Changes being contributed to official projects via Pull Request. Once merged upstream, these become standard features.

| Project | Branch | Documentation |
|---------|--------|---------------|
| munki CLI YAML support | `add-yaml-support` | [code/cli/munki/YAML_PR.md](code/cli/munki/YAML_PR.md) |
| MunkiAdmin YAML support | `add-yaml-support` (in MunkiAdmin repo) | [code/munkiadmin/YAML_SUPPORT.md](code/munkiadmin/YAML_SUPPORT.md) |

---

## Fork Customizations Summary

| Category | Files | Description |
|----------|-------|-------------|
| App Icons | 3 apps × icon sets | Custom liquid glass Macintosh icon |
| CLI Tools - munkiimport | +415 lines | Git integration, filename sanitization |
| Build System | build.sh + tools | Signing, notarization, YAML support |
| Version Files | 3 files | May use date-based versioning |
| Submodules | .gitmodules | munkipkg, munkiadmin, mwa2 |
| Development Files | .vscode/ | IDE configs |

---

## Quick Reference - Conflict Resolution

When merging from upstream, use these rules:

| File Type | Resolution |
|-----------|------------|
| Version/Info.plist files | Keep OURS (HEAD) |
| build.sh | Keep OURS (HEAD) |
| AppIcon.icon assets | Keep OURS (HEAD) |
| munkiimport.swift | CAREFUL - Re-apply our customizations if overwritten |
| .gitmodules | Keep OURS (HEAD) |
| .vscode/ | Keep OURS (HEAD) |
| Everything else | Accept THEIRS (upstream) |

---

## Detailed Customization Categories

### 1. App Icons - Custom Liquid Glass Macintosh

Custom icon assets for all three apps. Each app has:
- `AppIcon.icon/` folder with icon.json and Assets/
- `Assets.xcassets/AppIcon.appiconset/` with sized PNG files

**Managed Software Center**:
- `code/apps/Managed Software Center/Managed Software Center/AppIcon.icon/`
- `code/apps/Managed Software Center/Managed Software Center/Assets.xcassets/AppIcon.appiconset/`

**MunkiStatus**:
- `code/apps/MunkiStatus/MunkiStatus/AppIcon.icon/`
- `code/apps/MunkiStatus/MunkiStatus/Assets.xcassets/AppIcon.appiconset/`

**munki-notifier**:
- `code/apps/munki-notifier/munki-notifier/AppIcon.icon/`
- `code/apps/munki-notifier/munki-notifier/Assets.xcassets/AppIcon.appiconset/`

**Custom Assets**:
- `Macintosh orange.png` - Primary icon layer
- `Macintosh white.png` - Secondary icon layer
- Removed upstream basket/pencil/paintbrush/ruler layers

---

### 2. CLI Tools - munkiimport

**Location**: `code/cli/munki/munkiimport/munkiimport.swift`  
**Documentation**: [customizations.md](code/cli/munki/munkiimport/customizations.md)

Custom features added (+415 lines):
- **Git Integration**: Auto-pull before import with rebase fallback
- **Makecatalogs Refresh**: Silent catalog rebuild before import
- **Filename Sanitization**: Architecture suffixes (-Apple/-Intel)
- **Read-only Handling**: Graceful filesystem error handling
- **Extended Templates**: Script and array field copying
- **Architecture Editing**: Interactive supported_architectures editing
- **Enhanced Display**: Better pkginfo preview formatting

**Functions to Preserve During Merges**:
- `isGitRepository()`
- `runGitPull()`
- `sanitizeInstallerFilename()`
- `runMakecatalogs()`

---

### 3. Build System

**Location**: `build.sh` (repository root)

The `build.sh` script is a custom wrapper that provides:

1. **Simplified Build Process**: Single command to build complete package
2. **Environment Configuration**: .env file for secrets/certificates
3. **Signing Automation**: Code and package signing with Developer ID
4. **Notarization**: Apple notarization and stapling
5. **YAML Support**: Builds Swift tools with YAML capability
6. **Dynamic Versioning**: Build-time version injection (see [version-customizations.md](code/version-customizations.md))

| Feature | Description |
|---------|-------------|
| YAML Support Integration | Builds with YAML-enabled CLI tools |
| Code Signing Automation | .env-based certificate configuration |
| Notarization Workflow | Apple notarization integration |
| Progress Reporting | Color-coded output and logging |
| Dynamic Versioning | Date-based version injection at build time |

**Additional Build Tools Modified**:
- `code/tools/make_munki_mpkg.sh` - Package building (date-based version detection)
- `code/tools/make_swift_munki_pkg.sh` - Swift package building (date-based version detection)
- `code/tools/uninstall_munki.sh` - Uninstall script
- `code/tools/pkgresources/Scripts_app/postinstall` - Post-install script

#### Usage

```bash
# Build unsigned package
./build.sh

# Build and sign package
./build.sh --sign

# Build, sign, and notarize package
./build.sh --sign --notarize

# Specify output directory
./build.sh --sign --output ~/Downloads
```

#### Configuration (.env File)

Create a `.env` file in the repository root with your signing credentials:

```bash
# Code Signing Certificates
APP_SIGNING_CERT="Developer ID Application: Your Name (TEAM_ID)"
PKG_SIGNING_CERT="Developer ID Installer: Your Name (TEAM_ID)"

# Notarization
NOTARY_PROFILE="NOTARY_PROFILE"
TEAM_ID="YOUR_TEAM_ID"

# Output
OUTPUT_DIR="$HOME/Desktop"
```

**Security Note**: The `.env` file is in `.gitignore` and should never be committed.

#### Script Features

**Environment Loading**:
```bash
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^[[:space:]]*$' | xargs)
fi
```

**Certificate Validation** (before signing):
```bash
if ! security find-identity -v -p codesigning | grep -q "$APP_SIGNING_CERT"; then
    echo "App signing certificate not found in keychain"
    exit 1
fi
```

**Notarization Workflow**:
```bash
# Submit for notarization
xcrun notarytool submit "$PKG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# Staple the ticket
xcrun stapler staple "$PKG_PATH"
```

#### Dependencies

- Xcode Command Line Tools (`xcodebuild`)
- Git
- Developer ID certificates (for signing)
- Notarization credentials (for notarization)

#### Output

1. **Package**: `munkitools-X.X.X.pkg` in output directory
2. **Build Log**: `/tmp/munki_build_YYYYMMDD_HHMMSS.log`
3. **Notarization Log**: `/tmp/notarize.log` (if notarizing)

#### Setting Up Notarization

First-time setup for notarization credentials:

```bash
# Store credentials in keychain
xcrun notarytool store-credentials "NOTARY_PROFILE" \
    --apple-id "your-apple-id@example.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "app-specific-password"
```

Generate app-specific password at: https://appleid.apple.com

#### Troubleshooting

**Certificate Not Found**:
```bash
# List available signing certificates
security find-identity -v -p codesigning | grep "Developer ID"
security find-identity -v -p basic | grep "Developer ID"
```

**Notarization Fails**:
```bash
# Check notarization history
xcrun notarytool history --keychain-profile "NOTARY_PROFILE"

# Get detailed info on a submission
xcrun notarytool info <submission-id> --keychain-profile "NOTARY_PROFILE"

# Get log for failed submission
xcrun notarytool log <submission-id> --keychain-profile "NOTARY_PROFILE"
```

**Build Fails**: Check the build log at `/tmp/munki_build_*.log` for detailed error messages.

---

### 4. Version Files

**Location**: Multiple Info.plist and version files

Files with version numbers that may conflict:
- `code/cli/munki/shared/version.swift` - CLI tools version
- `code/apps/Managed Software Center/Managed Software Center/Info.plist` - MSC version
- `code/apps/MunkiStatus/MunkiStatus/Info.plist` - MunkiStatus version  
- `code/apps/munki-notifier/munki-notifier/Info.plist` - Notifier version

**Note**: Upstream uses semantic versioning (7.0.x), we may use date-based versioning (2025.x.x).

---

### 5. Submodules

**Location**: `.gitmodules`

Added submodules for related projects:
- `code/cli/munki/munkipkg` - munkipkg tool
- `code/munkiadmin` - MunkiAdmin GUI
- `code/mwa2` - Munki Web Admin 2

---

### 6. Development Files

**VS Code Configuration**:
- `.vscode/launch.json` - Debug configurations
- `code/cli/munki/.vscode/tasks.json` - Build tasks

**Copilot Memory**:
- `.github/copilot-instructions.md` - AI assistant context

**Git Configuration**:
- `.gitignore` - Added `.env` for build secrets
- `.github/ISSUE_TEMPLATE/` - Removed (issues go to upstream)

**Test Scripts**:
- `code/cli/munki/test_build.sh` - Build testing
- `code/cli/munki/yaml_to_plist/yaml_to_plist.swift` - YAML conversion tool

**Sample Data** (can be deleted):
- `catalogs/all` - Empty test catalog file

---

### 7. Removed Files

**GitHub Issue Templates** (deleted):
- `.github/ISSUE_TEMPLATE/bug_report.md`
- `.github/ISSUE_TEMPLATE/feature_request.md`

Removed because this is a fork - issues should go to upstream munki/munki.

---

## NOT Fork Customizations (PR Contributions)

The following files appear in the diff but are **PR contributions** on the `add-yaml-support` branch, not fork customizations. Once the PR is merged upstream, these become standard features:

| File | Purpose |
|------|---------|
| `code/cli/munki/shared/utils/yamlutils.swift` | Core YAML utilities |
| `code/cli/munki/shared/utils/plistutils.swift` | YAML integration in plist handling |
| `code/cli/munki/makepkginfo/MPIconvert.swift` | `makepkginfo convert` subcommand |
| `code/cli/munki/manifestutil/MUconvert.swift` | `manifestutil convert` subcommand |
| `code/cli/munki/makecatalogs/makecatalogs.swift` | YAML pkgsinfo support |
| `code/cli/munki/manifestutil/MUdisplayManifest.swift` | YAML manifest support |
| `code/cli/munki/manifestutil/MUmanifestFileOperations.swift` | YAML manifest I/O |
| Various other CLI files | YAML format detection and handling |

**Branch**: `add-yaml-support`  
**Documentation**: [code/cli/munki/YAML_PR.md](code/cli/munki/YAML_PR.md)

---

## Upstream Sync Workflow

```bash
# 1. Add upstream remote (if not already added)
git remote add upstream https://github.com/munki/munki.git

# 2. Fetch latest changes
git fetch upstream

# 3. Create merge branch
git checkout -b sync-upstream-$(date +%Y%m%d)

# 4. Merge upstream main
git merge upstream/main

# 5. Resolve conflicts using Quick Reference table above
# 6. Verify customizations are intact (see checklist)
# 7. Test build
# 8. Push and create PR
```

---

## Verification Checklist

After merging upstream changes, verify:

### Code Customizations
- [ ] `munkiimport.swift` contains `isGitRepository()` function
- [ ] `munkiimport.swift` contains `sanitizeInstallerFilename()` function
- [ ] `munkiimport.swift` contains `runGitPull()` function

### Icons
- [ ] AppIcon.icon assets contain "Macintosh orange.png" and "Macintosh white.png"
- [ ] All three apps have custom icons (MSC, MunkiStatus, munki-notifier)

### Build System
- [ ] `build.sh` has YAML support and signing features
- [ ] `.gitmodules` contains munkipkg, munkiadmin, mwa2 submodules

### Build Verification
- [ ] `swift build -c release` completes successfully
- [ ] All 17 CLI targets build without errors
- [ ] Package installs and runs correctly

---

## Complete File List

<details>
<summary>All files different from upstream (click to expand)</summary>

### Fork Customizations Only (not in PR branch)
```
.github/copilot-instructions.md
.github/ISSUE_TEMPLATE/ (deleted)
.gitignore
.gitmodules
.vscode/launch.json
build.sh
catalogs/all
code/apps/Managed Software Center/Managed Software Center.xcodeproj/xcshareddata/xcschemes/
code/apps/Managed Software Center/*/AppIcon.icon/* 
code/apps/Managed Software Center/*/Assets.xcassets/AppIcon.appiconset/*
code/apps/MunkiStatus/*/AppIcon.icon/*
code/apps/MunkiStatus/*/Assets.xcassets/AppIcon.appiconset/*
code/apps/munki-notifier/*/AppIcon.icon/*
code/apps/munki-notifier/*/Assets.xcassets/AppIcon.appiconset/*
code/apps/munki-notifier/munki-notifier/Info.plist
code/cli/munki/.vscode/tasks.json
code/cli/munki/munkiimport/customizations.md
code/tools/make_munki_mpkg.sh
code/tools/make_swift_munki_pkg.sh
code/tools/pkgresources/Scripts_app/postinstall
code/tools/uninstall_munki.sh
```

### Shared with PR Branch (munkiimport has both PR and customization changes)
```
code/cli/munki/munkiimport/munkiimport.swift
```

### PR Contributions Only (on add-yaml-support branch)
```
code/cli/munki/shared/utils/yamlutils.swift
code/cli/munki/shared/utils/plistutils.swift
code/cli/munki/makepkginfo/MPIconvert.swift
code/cli/munki/manifestutil/MUconvert.swift
(and other YAML-related files)
```

</details>
