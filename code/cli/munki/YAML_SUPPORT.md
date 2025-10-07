# Munki v7 YAML Support

## Overview

Munki v7 includes native YAML support, fully integrated into all tools using the **Xcode build system** (following the official Munki project structure).

## Build System

### Xcode Build System (Current)
- Uses `munki.xcodeproj` for build configuration
- YAML support integrated into existing tools
- Required: `xcodebuild` command or Xcode IDE
- **Follows official Munki project structure**

## Current Tools with YAML Support

All tools built with Xcode and fully integrated:

### 1. makepkginfo convert
Convert pkginfo files between YAML and plist formats.

**Single file conversion:**
```bash
# plist to YAML
makepkginfo convert Firefox-123.0.plist Firefox-123.0.yaml

# YAML to plist
makepkginfo convert Firefox-123.0.yaml Firefox-123.0.plist
```

**Batch directory conversion:**
```bash
# Convert all pkginfo files to YAML
makepkginfo convert /path/to/pkgsinfo --to-yaml --backup

# Convert all pkginfo files to plist
makepkginfo convert /path/to/pkgsinfo --to-plist --backup

# Dry run to preview changes
makepkginfo convert /path/to/pkgsinfo --to-yaml --dry-run --verbose
```

**Options:**
- `--to-yaml` - Convert all files to YAML format
- `--to-plist` - Convert all files to plist format
- `--backup` - Create `.backup` copies of original files
- `--dry-run` - Show what would be done without making changes
- `--verbose` - Detailed progress output
- `--force` - Overwrite existing files

### 2. manifestutil convert
Convert manifest files between YAML and plist formats.

**Single file conversion:**
```bash
# plist to YAML
manifestutil convert production production.yaml

# YAML to plist
manifestutil convert production.yaml production
```

**Batch directory conversion:**
```bash
# Convert all manifests to YAML
manifestutil convert /path/to/manifests --to-yaml --backup

# Convert all manifests to plist
manifestutil convert /path/to/manifests --to-plist --backup
```

**Options:** Same as makepkginfo convert

### 3. All Other Munki Tools
The following tools also support YAML natively (no conversion needed):

**Admin Tools:**
- `makecatalogs` - Reads YAML pkginfo files, generates catalogs
- `munkiimport` - Imports packages, can output YAML pkginfo
- `repoclean` - Works with YAML repositories

**Client Tools:**
- `managedsoftwareupdate` - Reads YAML manifests and catalogs
- All other client tools have YAML support

## Building from Source

### Build All Tools with Xcode

```bash
cd /Users/rod/Developer/munki/code/cli/munki

# Build all 16 Munki CLI tools
xcodebuild -project munki.xcodeproj -scheme ALL_BUILD -configuration Release build

# Or build individual tools
xcodebuild -project munki.xcodeproj -scheme makepkginfo -configuration Release build
xcodebuild -project munki.xcodeproj -scheme manifestutil -configuration Release build
xcodebuild -project munki.xcodeproj -scheme makecatalogs -configuration Release build
xcodebuild -project munki.xcodeproj -scheme munkiimport -configuration Release build
# ... etc
```

### Installation

Built binaries are located at:
```
/Users/rod/Library/Developer/Xcode/DerivedData/munki-*/Build/Products/Release/
```

Copy to your installation location:
```bash
sudo cp /Users/rod/Library/Developer/Xcode/DerivedData/munki-*/Build/Products/Release/* /usr/local/munki/
```

Or use the project's build scripts.

## Converting Between YAML and plist

Use the built-in conversion commands to migrate existing repositories or convert individual files.

## Benefits of the New Approach

1. **Consistency** - Uses same build system as official Munki project
2. **Integration** - YAML support built into existing tools, not separate utilities
3. **Maintenance** - Single codebase, easier to maintain
4. **Features** - Access to all Munki tool features with YAML support
5. **Documentation** - Follows official Munki documentation patterns
6. **User Experience** - Familiar commands for existing Munki users

## File Structure

```
code/cli/munki/
├── munki.xcodeproj/          # Xcode project (build system)
├── makepkginfo/
│   ├── makepkginfo.swift     # Main tool
│   ├── MPKconvert.swift      # Convert subcommand
│   └── MPKcreate.swift       # Create subcommand (default)
├── manifestutil/
│   ├── manifestutil.swift    # Main tool
│   └── MUconvert.swift       # Convert subcommand
└── shared/                   # Shared code for all tools
    └── YAMLSupport.swift
```

## Support

For issues or questions:
1. Check tool help: `makepkginfo convert --help`
2. Check manifest tool help: `manifestutil convert --help`
3. Refer to official Munki documentation
4. See YAML support documentation in this repository

---

**Last Updated:** October 5, 2025
