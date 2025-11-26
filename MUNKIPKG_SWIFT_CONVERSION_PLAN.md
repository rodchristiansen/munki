# munkipkg Swift Integration Plan

## 🎉 Major Discovery: Existing Swift Implementation Found!

During the upstream sync process, we discovered that the upstream `munki-pkg` repository already has a **substantial Swift implementation** in the `swift` branch! This changes our approach from "conversion" to "integration and completion".

## Overview
This document outlines the plan to integrate and complete the existing Swift-based `munkipkg` implementation as part of the Munki v7 project. The submodule now points to the Swift branch which contains a partially complete Swift implementation.

## Current State Analysis

### 🔄 Repository Status (UPDATED)
- **Submodule Location**: `code/cli/munki/munkipkg` (now on Swift branch)
- **Python Script**: Still available at `munkipkg` (1057 lines) - serves as reference
- **Swift Implementation**: Found in `swift/munkipkg/` directory with Xcode project

### 🚀 Existing Swift Implementation Features
**Already Implemented:**
- ✅ **ArgumentParser CLI Structure**: Complete command-line interface using Swift ArgumentParser
- ✅ **BuildInfo Data Models**: Codable structs for configuration parsing
- ✅ **Package Signing Support**: SigningInfo struct with certificate handling
- ✅ **Notarization Support**: NotarizationInfo struct for Apple notarization
- ✅ **Multiple Config Formats**: Plist, JSON parsing (YAML marked as not supported yet)
- ✅ **Xcode Project Structure**: Complete with tests and proper Swift project setup
- ✅ **Error Handling**: Custom error types with inheritance

**Key Swift Files Discovered:**
1. `munkipkg.swift` - Main command structure with ArgumentParser
2. `buildinfo.swift` - Configuration data models (BuildInfo, SigningInfo, NotarizationInfo)
3. `munkipkgoptions.swift` - Command-line option parsing and validation
4. `cliutils.swift` - CLI utility functions
5. `errors.swift` - Custom error handling
6. `BuildInfoTests.swift` - Unit tests for configuration parsing

### 📋 Features Still Needed (Based on Python Reference)
1. **Package Building**: Core `pkgbuild` and `productbuild` execution
2. **Project Creation**: `--create` flag implementation with templates
3. **Package Import**: `--import` flag to convert existing packages
4. **Payload Processing**: File system operations for payload directory
5. **Scripts Handling**: Processing of preinstall/postinstall scripts
6. **BOM Export/Sync**: Git integration features for tracking file permissions
7. **Distribution Packages**: Support for complex package structures

### Dependencies Analysis
- **Python Standard Library**: `glob`, `json`, `optparse`, `os`, `plistlib`, `shutil`, `stat`, `subprocess`, `sys`, `tempfile`
- **External Dependencies**: `yaml` (PyYAML) - optional
- **System Tools**: `ditto`, `lsbom`, `pkgbuild`, `pkgutil`, `productbuild`

## Swift Integration Plan (REVISED)

### Phase 1: Assessment and Setup (COMPLETED ✅)
- [x] **Submodule Integration**: Added munkipkg as submodule on Swift branch
- [x] **Existing Code Analysis**: Reviewed current Swift implementation
- [x] **Architecture Understanding**: Studied ArgumentParser structure and data models

### Phase 2: Complete Core Building Functionality (2-3 weeks)
- [ ] **Package Building Engine**: Implement the core package creation logic
  - Process payload directory structure
  - Execute `pkgbuild` with proper parameters
  - Handle distribution-style packages via `productbuild`
- [ ] **Build Info Processing**: Complete the configuration pipeline
  - Ensure plist/JSON parsing works end-to-end
  - Add YAML support integration with Yams
  - Validate build parameters before execution
- [ ] **File System Operations**: Implement payload and scripts processing
  - Payload directory validation and processing
  - Scripts directory handling (preinstall/postinstall)
  - Permission and ownership management

### Phase 3: Advanced Features (2-3 weeks)
- [ ] **Project Creation (`--create`)**: Template generation functionality
- [ ] **Package Import (`--import`)**: Convert existing packages to projects
- [ ] **BOM Integration**: Git-friendly file tracking
  - Export BOM info (`--export-bom-info`)
  - Sync from BOM info (`--sync`)
- [ ] **Enhanced Signing/Notarization**: Complete the existing partial implementation

### Phase 4: Integration with Munki v7 (1 week)
- [ ] **Package.swift Integration**: Add munkipkg to the main Swift package
- [ ] **Shared Library Usage**: Integrate with MunkiShared where appropriate  
- [ ] **Consistent Patterns**: Ensure coding style matches other Munki tools
- [ ] **Build System**: Add to automated build and test processes

## Revised Implementation Strategy

### 1. Build on Existing Foundation
Instead of starting from scratch, we'll:
- Use the existing ArgumentParser structure as-is
- Complete the BuildInfo implementation 
- Add missing core functionality to the established architecture

### 2. Reference-Driven Development
- Use Python implementation as functional reference
- Ensure feature parity through systematic comparison
- Validate against existing munkipkg projects

### 3. Swift Package Manager Integration
```swift
// Add to main Package.swift in munki CLI tools
.executableTarget(
    name: "munkipkg",
    dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        "Yams",
        "MunkiShared"
    ],
    path: "munkipkg/swift/munkipkg/munkipkg",
    sources: ["munkipkg.swift", "buildinfo.swift", "munkipkgoptions.swift", 
              "cliutils.swift", "errors.swift"]
)
```

### 6. Dependencies Required
- **ArgumentParser**: Command-line argument parsing (already available)
- **Yams**: YAML support (already available)
- **Foundation**: Core macOS APIs
- **System frameworks**: For process execution and file operations

### 7. Migration Strategy
- [ ] Maintain backward compatibility with existing project formats
- [ ] Create comprehensive test suite using existing Python tool as reference
- [ ] Parallel development approach - keep Python version until Swift version is complete
- [ ] Validation against existing package projects

## Implementation Details

### Command Line Interface
```swift
// Proposed ArgumentParser structure
struct MunkiPkg: ParsableCommand {
    @Flag(help: "Create a new package project")
    var create: Bool = false
    
    @Flag(help: "Import existing package")
    var `import`: Bool = false
    
    @Option(help: "Output format (plist, json, yaml)")
    var format: String?
    
    @Flag(help: "Export BOM info")
    var exportBomInfo: Bool = false
    
    @Flag(help: "Sync from BOM info") 
    var sync: Bool = false
    
    @Flag(help: "Quiet mode")
    var quiet: Bool = false
    
    @Argument(help: "Project directory path")
    var projectPath: String?
}
```

### Configuration Data Models
```swift
struct BuildInfo: Codable {
    var distributionStyle: Bool = false
    var identifier: String
    var installLocation: String = "/"
    var name: String
    var ownership: String = "recommended"
    var postinstallAction: String = "none"
    var preserveXattr: Bool = false
    var suppressBundleRelocation: Bool = true
    var version: String = "1.0"
    var signingInfo: SigningInfo?
    var productId: String?
}

struct SigningInfo: Codable {
    var identity: String
    var keychain: String?
    var additionalCertNames: [String]?
    var timestamp: Bool = false
}
```

## Testing Strategy
1. **Unit Tests**: Test individual components and data models
2. **Integration Tests**: Test complete workflows
3. **Compatibility Tests**: Ensure projects created by Python version work with Swift version
4. **Performance Tests**: Compare performance with Python implementation

## Timeline Estimate (REVISED)
- **Phase 1 (Assessment)**: ✅ COMPLETED
- **Phase 2 (Core Building)**: 2-3 weeks  
- **Phase 3 (Advanced Features)**: 2-3 weeks
- **Phase 4 (Integration)**: 1 week
- **Total Estimated Time**: 5-7 weeks (reduced from 5-8 weeks)

## Success Criteria (UPDATED)
1. ✅ Leverage existing Swift foundation effectively
2. ✅ Feature parity with Python implementation
3. ✅ All existing package projects continue to work
4. ✅ Performance equal to or better than Python version
5. ✅ Fully integrated with Munki v7 Swift Package Manager structure
6. ✅ Comprehensive test coverage (building on existing tests)
7. ✅ Documentation updated for Swift version

## Next Steps (PRIORITIZED)
1. **Study Existing Swift Code**: Understand current implementation patterns and architecture
2. **Implement Package Building**: Complete the core functionality using existing data models
3. **Test Against Python Version**: Ensure compatibility and feature parity
4. **Add to Main Package.swift**: Integrate with Munki v7 build system
5. **Complete Missing Features**: Add project creation, import, and BOM functionality

---
*This plan has been significantly updated after discovering the existing Swift implementation. The focus has shifted from conversion to completion and integration.*