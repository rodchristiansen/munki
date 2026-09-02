# Build System Customizations

**Purpose:** Documents custom build scripts and packaging for our Munki fork.

**Location:** Root + `code/tools/`  
**Upstream:** `https://github.com/munki/munki/tree/main/code/tools`

---

## Overview

We maintain custom build infrastructure that wraps upstream scripts with:
- Environment-based configuration (`.env` files)
- Code signing and notarization support
- Colored output and progress tracking
- YAML support integration

---

## Custom Build Scripts

### 1. `build.sh` (Root)

**Purpose:** Main entry point for building Munki packages.

**Features:**
- `.env` file configuration loading
- Developer ID code signing
- Apple notarization support
- Output directory control
- Colored terminal output

**Usage:**
```bash
./build.sh                    # Build unsigned package
./build.sh --sign             # Build and sign package
./build.sh --sign --notarize  # Build, sign, and notarize package
./build.sh -o ~/Downloads     # Custom output directory
```

**Configuration (.env):**
```bash
# .env file (not committed to git)
APP_SIGNING_CERT="Developer ID Application: Your Name (TEAMID)"
PKG_SIGNING_CERT="Developer ID Installer: Your Name (TEAMID)"
NOTARY_PROFILE="NOTARY_PROFILE"
TEAM_ID="YOURTEAMID"
OUTPUT_DIR="$HOME/Desktop"
```

### 2. `build.command` (Root)

**Purpose:** Double-click launcher for `build.sh`.

Opens Terminal and runs the build script for users who prefer GUI interaction.

### 3. `code/tools/make_munki_mpkg.sh`

**Purpose:** Creates the Munki meta-package installer.

**Our Customizations:**
- Version numbering integration
- Custom component packages

(App path references match upstream - the "Software Center" rename was reverted.)

### 4. `code/tools/make_swift_munki_pkg.sh`

**Purpose:** Builds Swift-based command-line tools into packages.

**Our Customizations:**
- YAML support inclusion
- Custom tool paths (`libexec/` structure)
- Xcode build configuration

---

## Removed Scripts

These upstream scripts have been removed in our fork:

| Script | Reason |
|--------|--------|
| `build_python_framework.sh` | Munki 7 is pure Swift, no Python framework needed |
| `py3_requirements.txt` | No longer building Python components |

---

## Build Directory Structure

```
code/build/
├── Build/                    # Xcode build products
├── binaries/                 # Compiled binaries for packaging
├── CompilationCache.noindex/ # Xcode compilation cache
├── Logs/                     # Build logs
├── ModuleCache.noindex/      # Swift module cache
├── SDKStatCaches.noindex/    # SDK caches
└── SourcePackages/           # SPM downloaded packages (if any)
```

---

## Signing & Notarization

### Certificate Setup

1. **Get certificates from Apple Developer Portal:**
   - "Developer ID Application" certificate
   - "Developer ID Installer" certificate

2. **Create notarization profile:**
   ```bash
   xcrun notarytool store-credentials "NOTARY_PROFILE" \
     --apple-id "your@email.com" \
     --team-id "YOURTEAMID" \
     --password "app-specific-password"
   ```

3. **Configure `.env`:**
   ```bash
   cp .env.example .env
   # Edit .env with your values
   ```

### Build Artifacts

After successful build:
```
~/Desktop/
├── munkitools-7.0.3.pkg           # Unsigned package (--sign not used)
├── munkitools-7.0.3-signed.pkg    # Signed package
└── munkitools-7.0.3-notarized.pkg # Signed + notarized
```

---

## Merge Strategy

**Files to preserve:**

| File | Action |
|------|--------|
| `build.sh` | Keep OURS |
| `build.command` | Keep OURS |
| `.env` | Never committed |
| `.env.example` | Keep OURS |

**Files to merge carefully:**

| File | Action |
|------|--------|
| `code/tools/make_munki_mpkg.sh` | Review changes, preserve path customizations |
| `code/tools/make_swift_munki_pkg.sh` | Review changes, preserve tool paths |

---

## Verification

After building:

```bash
# Check package contents
pkgutil --payload-files munkitools-*.pkg | head -20

# Verify signature (if signed)
pkgutil --check-signature munkitools-*.pkg

# Check notarization (if notarized)
spctl --assess --type install -v munkitools-*.pkg
```

---

## Troubleshooting

### Code Signing Fails
```
✗ Signing certificates not configured
```
**Solution:** Create `.env` file with certificate names.

### Notarization Fails
```
✗ Notarization profile not configured
```
**Solution:** Run `xcrun notarytool store-credentials` to create profile.

### Build Products Not Found
```
✗ xcodebuild failed
```
**Solution:** 
1. Open `code/cli/munki/munki.xcodeproj` in Xcode
2. Build manually to see errors
3. Fix issues and retry `./build.sh`

---

## See Also

- [Master Customizations Index](../../CUSTOMIZATIONS.md)
- [Launchd Customizations](../../launchd/customizations.md)
- [munkiimport Customizations](../cli/munki/munkiimport/customizations.md)
