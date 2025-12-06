# Version Files Customizations

Documenting version-related files and the dynamic versioning system used in this fork.

---

## Summary

| File | Purpose |
|------|---------|
| `code/cli/munki/shared/version.swift` | CLI tools version (placeholder for build-time injection) |
| `code/tools/make_swift_munki_pkg.sh` | Build script with date-based version detection |
| `build.sh` | Wrapper script that injects version at build time |

---

## Version Formats

| Source | Format | Example |
|--------|--------|---------|
| Upstream | Semantic versioning + revision | `7.0.3.5459` |
| This fork | Date-based (dynamic) | `2025.12.06.1316` |

**Format**: `YYYY.MM.DD.HHMM`

---

## Dynamic Version System

This fork uses **build-time version injection** rather than hardcoded versions.

### How It Works

1. **version.swift** contains a placeholder: `__BUILD_VERSION__`
2. **build.sh** generates version from current date/time: `$(date +"%Y.%m.%d.%H%M")`
3. **build.sh** injects the version into version.swift before building
4. **make_swift_munki_pkg.sh** detects date-based format and skips revision suffix
5. **build.sh** restores the placeholder after build (via trap)

### Version Detection Regex

The build script detects date-based versions with this pattern:
```bash
if [[ "$MUNKIVERS" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{4}$ ]]; then
    # Date-based version - use as-is (no .5459 suffix)
    VERSION=$MUNKIVERS
else
    # Traditional version - append revision
    VERSION=$MUNKIVERS.$SVNREV
fi
```

---

## File Details

### code/cli/munki/shared/version.swift

**Content** (at rest):
```swift
/// one single place to define a version for CLI tools
/// This value is replaced dynamically by build.sh during the build process
let CLI_TOOLS_VERSION = "__BUILD_VERSION__"

/// Returns version of Munki tools
func getVersion() -> String {
    return CLI_TOOLS_VERSION
}
```

**During build** (temporary):
```swift
let CLI_TOOLS_VERSION = "2025.12.06.1316"
```

**Merge Resolution**: Keep OUR version with `__BUILD_VERSION__` placeholder.

---

### build.sh (Root)

Injects version before calling make_swift_munki_pkg.sh:

```bash
# Generate dynamic version string (YYYY.MM.DD.HHMM format)
BUILD_VERSION=$(date +"%Y.%m.%d.%H%M")
VERSION_FILE="$SCRIPT_DIR/code/cli/munki/shared/version.swift"

# Replace placeholder in version.swift
sed -i '' "s/__BUILD_VERSION__/$BUILD_VERSION/g" "$VERSION_FILE"

# Trap to restore version on exit (success or failure)
trap restore_version EXIT
```

---

### code/tools/make_swift_munki_pkg.sh

Modified to detect date-based versions and skip revision suffix:

**Lines ~216-224**:
```bash
# Check if version is date-based (YYYY.MM.DD.HHMM format) - if so, don't append revision
if [[ "$MUNKIVERS" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{4}$ ]]; then
    VERSION=$MUNKIVERS
else
    VERSION=$MUNKIVERS.$SVNREV
fi
```

**Lines ~293-299** (metapackage version):
```bash
if [[ "$MUNKIVERS" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{4}$ ]]; then
    DISTPKGVERSION=$MUNKIVERS
else
    DISTPKGVERSION=$MUNKIVERS.$DISTPKGSVNREV
fi
```

**Lines ~256-264** (Apps package version):
```bash
if [[ "$MUNKIVERS" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{4}$ ]]; then
    # Use the date-based version for apps too
    APPSVERSION=$MUNKIVERS
else
    # append the APPSSVNREV for traditional versioning
    APPSVERSION=$APPSVERSION.$APPSSVNREV
fi
```

---

## Build Output

With dynamic versioning, build output shows clean versions:

```
Build variables

  munki core tools version: 2025.12.06.1341
  LaunchAgents/LaunchDaemons version: 7.0.0.5458
  Apps package version: 2025.12.06.1341

  metapackage version: 2025.12.06.1341
```

Note: LaunchAgents still uses traditional versioning with revision suffix (reads from `launchd/version.plist`).

---

## Merge Strategy

### During Upstream Merges

1. **version.swift**: Keep ours with `__BUILD_VERSION__` placeholder
   ```bash
   git checkout --ours code/cli/munki/shared/version.swift
   ```

2. **make_swift_munki_pkg.sh**: Manually re-apply date-based version detection if overwritten

3. **build.sh**: Keep ours entirely (fork customization)

---

## Manual Version Override

To build with a specific version instead of current timestamp:

```bash
# Set version manually before build
VERSION_FILE="code/cli/munki/shared/version.swift"
sed -i '' "s/__BUILD_VERSION__/2025.12.25.0000/g" "$VERSION_FILE"

# Run build directly (bypass build.sh version injection)
bash code/tools/make_swift_munki_pkg.sh -o ~/Desktop

# Restore placeholder
sed -i '' "s/2025.12.25.0000/__BUILD_VERSION__/g" "$VERSION_FILE"
```

---

## Checking Current State

```bash
# Check if placeholder is in place (should show __BUILD_VERSION__)
grep "CLI_TOOLS_VERSION" code/cli/munki/shared/version.swift

# Test version format detection
TEST="2025.12.06.1316"
[[ "$TEST" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{4}$ ]] && echo "Date-based" || echo "Traditional"
```

---

## Related Files

- `build.sh` - Main build wrapper with version injection
- `code/tools/make_swift_munki_pkg.sh` - Package build script with version detection
- `code/cli/munki/shared/version.swift` - Version placeholder file
- `CUSTOMIZATIONS.md` - Overall fork customizations index
