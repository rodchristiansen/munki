# YAML Support - Upstream PR Contribution

Documenting YAML support features being contributed to the official munki project via Pull Request. These changes are NOT fork-specific customizations - they are intended to become part of the official project.

**Branch**: `add-yaml-support`  
**Remote**: `origin/add-yaml-support`  
**PR Target**: https://github.com/munki/munki (upstream)  
**Status**: Active PR

---

## Summary

This is a contribution to the official munki project, not a fork customization. Once merged upstream, this code will be maintained by the munki project.

| Component | Description | Status |
|-----------|-------------|--------|
| yamlutils.swift | Core YAML reading/writing utilities | Complete |
| makepkginfo convert | Subcommand for pkginfo format conversion | Complete |
| manifestutil convert | Subcommand for manifest format conversion | Complete |
| Yams dependency | Swift YAML parsing library | Integrated |

---

## Branch Management

### Relationship to Main Branch

```
munki/munki (upstream)
    |
    +-- add-yaml-support (PR branch - clean, minimal changes)
    |
    +-- main (fork branch - includes PR + fork customizations)
```

The `add-yaml-support` branch contains ONLY the YAML support changes intended for upstream. The `main` branch includes these changes PLUS fork-specific customizations.

### Keeping the PR Branch Clean

When working on the PR:

```bash
# Switch to PR branch
git checkout add-yaml-support

# Do NOT merge main into this branch
# Only make YAML-related changes here

# Push to origin for PR
git push origin add-yaml-support
```

### Syncing Main with PR Changes

After making PR updates:

```bash
# Switch to main
git checkout main

# Merge PR branch changes
git merge add-yaml-support

# Resolve any conflicts (keep fork customizations)
```

---

## Files in the PR

### Core YAML Support

| File | Purpose |
|------|---------|
| `code/cli/munki/shared/utils/yamlutils.swift` | YAML read/write utilities, type normalization |
| `code/cli/munki/munki.xcodeproj/project.pbxproj` | Xcode project with Yams dependency |

### CLI Tool Enhancements

| File | Change |
|------|--------|
| `code/cli/munki/makepkginfo/makepkginfo.swift` | Added `convert` subcommand |
| `code/cli/munki/manifestutil/manifestutil.swift` | Added `convert` subcommand |

### Dependencies

| Dependency | Purpose | Integration |
|------------|---------|-------------|
| Yams | Swift YAML parsing | Xcode Swift Package Manager |

---

## Features Contributed

### 1. YAML File Detection

```swift
func isYamlFile(_ filepath: String) -> Bool {
    let fileExtension = (filepath as NSString).pathExtension.lowercased()
    return fileExtension == "yaml" || fileExtension == "yml"
}
```

### 2. YAML Reading with Type Normalization

Handles the common YAML pitfall where version numbers become floats:

```yaml
# Problem: unquoted version becomes float 10.12
minimum_os_version: 10.12

# Solution: yamlutils normalizes to string "10.12"
```

### 3. Format Conversion Commands

```bash
# Convert pkginfo between formats
makepkginfo convert input.plist output.yaml
makepkginfo convert input.yaml output.plist

# Convert manifests between formats
manifestutil convert input.plist output.yaml
manifestutil convert input.yaml output.plist
```

---

## NOT Part of This PR

The following are fork-specific customizations documented elsewhere:

- Git pull automation in munkiimport (see `code/cli/munki/munkiimport/customizations.md`)
- Filename sanitization with -Apple/-Intel suffixes
- Custom branding assets
- Launchd path customizations
- Custom build.sh wrapper
- MunkiAdmin YAML support (separate project)

---

## Testing the PR Branch

```bash
# Build from PR branch
git checkout add-yaml-support
cd code/cli/munki
xcodebuild -project munki.xcodeproj -scheme makepkginfo -configuration Release

# Test conversion
./build/Release/makepkginfo convert test.plist test.yaml
./build/Release/makepkginfo convert test.yaml test_roundtrip.plist

# Verify round-trip integrity
diff test.plist test_roundtrip.plist
```

---

## PR Checklist

Before pushing PR updates:

- [ ] Branch contains ONLY YAML-related changes
- [ ] No fork-specific customizations included
- [ ] No custom branding/paths
- [ ] Builds cleanly from fresh clone
- [ ] Conversion commands work correctly
- [ ] Round-trip conversion preserves data

---

## After Upstream Merge

Once the PR is merged to munki/munki:

1. The `add-yaml-support` branch can be archived or deleted
2. Sync main branch from upstream to get official YAML support
3. Remove this document or mark as historical
4. YAML support will no longer be a "customization" - it will be standard munki
