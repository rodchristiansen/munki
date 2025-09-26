# munkipkg Swift Conversion Plan

## Overview
This document outlines the plan to convert the Python-based `munkipkg` tool to Swift as part of the Munki v7 project. The `munkipkg` tool is currently a Python script that builds macOS packages from project directories in a consistent, repeatable manner.

## Current Implementation Analysis

### Python Script Structure (munkipkg)
- **Location**: `code/cli/munki/munkipkg/munkipkg` (1057 lines of Python)
- **Main Functions**:
  - Package creation from project directories
  - Import existing packages into projects
  - Build flat packages using Apple's `pkgbuild` and `productbuild`
  - Support for XML plist, JSON, and YAML build configuration files
  - Package signing capabilities
  - Bom info export/sync for git compatibility

### Key Features to Port
1. **Project Creation**: `--create` flag to create new package project templates
2. **Package Import**: `--import` flag to convert existing packages to projects
3. **Package Building**: Main functionality to build packages from project directories
4. **Multiple Config Formats**: Support for plist, JSON, and YAML build-info files
5. **Package Signing**: Integration with macOS signing infrastructure
6. **Git Integration**: Bom export/sync for version control compatibility
7. **Distribution Packages**: Support for distribution-style packages

### Dependencies Analysis
- **Python Standard Library**: `glob`, `json`, `optparse`, `os`, `plistlib`, `shutil`, `stat`, `subprocess`, `sys`, `tempfile`
- **External Dependencies**: `yaml` (PyYAML) - optional
- **System Tools**: `ditto`, `lsbom`, `pkgbuild`, `pkgutil`, `productbuild`

## Swift Implementation Plan

### 1. Project Structure Setup
- [ ] Add `munkipkg` target to `Package.swift`
- [ ] Create `munkipkg/` directory structure
- [ ] Set up main executable target with dependencies

### 2. Core Architecture Design
- [ ] Design Swift equivalent command-line interface using ArgumentParser
- [ ] Create data models for build-info structures
- [ ] Implement file system operations using Foundation
- [ ] Design error handling and logging system

### 3. Configuration File Support
- [ ] **Plist Support**: Use `PropertyListSerialization` from Foundation
- [ ] **JSON Support**: Use `JSONSerialization` from Foundation  
- [ ] **YAML Support**: Integrate existing Yams dependency from other Munki tools
- [ ] Create unified configuration parser with format auto-detection

### 4. Core Functionality Implementation

#### Phase 1: Basic Package Building
- [ ] Implement project directory validation
- [ ] Create payload directory processing
- [ ] Implement scripts directory handling
- [ ] Basic `pkgbuild` command execution
- [ ] Error handling and validation

#### Phase 2: Advanced Features
- [ ] Package import functionality (`--import`)
- [ ] Project creation (`--create`) with templates
- [ ] Distribution package support
- [ ] Package signing integration
- [ ] Bom export/sync for git compatibility

#### Phase 3: Optimization and Polish
- [ ] Performance optimization
- [ ] Comprehensive error messages
- [ ] Help system and documentation
- [ ] Unit tests and integration tests

### 5. Integration with Munki v7
- [ ] Update `Package.swift` to include munkipkg executable
- [ ] Ensure consistent coding patterns with other Munki Swift tools
- [ ] Integrate with shared MunkiShared library where appropriate
- [ ] Add to build and test systems

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

## Timeline Estimate
- **Phase 1 (Basic Building)**: 2-3 weeks
- **Phase 2 (Advanced Features)**: 2-3 weeks  
- **Phase 3 (Polish & Testing)**: 1-2 weeks
- **Total Estimated Time**: 5-8 weeks

## Success Criteria
1. ✅ Feature parity with Python implementation
2. ✅ All existing package projects continue to work
3. ✅ Performance equal to or better than Python version
4. ✅ Consistent with other Munki v7 Swift tools
5. ✅ Comprehensive test coverage
6. ✅ Documentation updated for Swift version

## Next Steps
1. Begin with Package.swift updates to add munkipkg target
2. Create basic command-line structure using ArgumentParser
3. Implement configuration file parsing
4. Start with basic package building functionality
5. Iterative development with testing against Python version

---
*This plan will be updated as development progresses and requirements are refined.*