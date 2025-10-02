//
//  yaml_migrate.swift
//  yaml_migrate
//
//  Created for Munki v7 YAML migration support
//  Copyright 2024-2025 Greg Neagle.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import ArgumentParser
import Foundation
import Yams

@main
struct YamlMigrate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "yaml_migrate",
        abstract: "Migrate Munki repository files from plist to YAML format",
        discussion: """
        This tool converts manifests and pkginfo files in a Munki repository from plist format to YAML format.
        
        It will recursively scan the specified directories and convert all .plist files to .yaml files.
        The original files can be backed up or replaced based on the options provided.
        
        Examples:
          # Migrate all manifests and pkginfo files, keeping backups
          yaml_migrate /path/to/munki/repo --backup
          
          # Migrate only manifests, replacing originals
          yaml_migrate /path/to/munki/repo --manifests-only --no-backup
          
          # Dry run to see what would be converted
          yaml_migrate /path/to/munki/repo --dry-run
        """
    )
    
    @Argument(help: "Path to the Munki repository root")
    var repoPath: String
    
    @Flag(name: .long, help: "Only migrate manifest files")
    var manifestsOnly = false
    
    @Flag(name: .long, help: "Only migrate pkginfo files")
    var pkginfoOnly = false
    
    @Flag(name: .long, help: "Create backup copies of original files")
    var backup = false
    
    @Flag(name: .long, help: "Don't create backup copies of original files")
    var noBackup = false
    
    @Flag(name: .long, help: "Show what would be done without making changes")
    var dryRun = false
    
    @Flag(name: .short, help: "Verbose output")
    var verbose = false
    
    @Flag(name: .long, help: "Force overwrite existing YAML files")
    var force = false
    
    mutating func run() throws {
        // Handle backup flag logic - default to true unless explicitly disabled
        let shouldBackup = !noBackup && (backup || (!backup && !noBackup))
        
        let repoURL = URL(fileURLWithPath: repoPath)
        
        // Validate repository path
        guard FileManager.default.fileExists(atPath: repoPath) else {
            throw ValidationError("Repository path does not exist: \(repoPath)")
        }
        
        var stats = MigrationStats()
        
        // Determine which directories to process
        let directories = getDirectoriesToProcess()
        
        if verbose {
            print("Starting YAML migration...")
            print("Repository: \(repoPath)")
            print("Backup: \(shouldBackup ? "enabled" : "disabled")")
            print("Dry run: \(dryRun ? "enabled" : "disabled")")
            print("Directories to process: \(directories.joined(separator: ", "))")
        }
        
        for directory in directories {
            let dirURL = repoURL.appendingPathComponent(directory)
            if FileManager.default.fileExists(atPath: dirURL.path) {
                try processDirectory(dirURL, stats: &stats, backup: shouldBackup)
            } else if verbose {
                print("Directory not found, skipping: \(dirURL.path)")
            }
        }
        
        // Print summary
        printSummary(stats)
    }
    
    /// Recursively converts NSMutableDictionary and NSMutableArray objects to native Swift types
    private static func convertToNativeSwiftTypes(_ object: Any) -> Any {
        if let dict = object as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, value) in dict {
                if let stringKey = key as? String {
                    result[stringKey] = convertToNativeSwiftTypes(value)
                }
            }
            return result
        } else if let array = object as? NSArray {
            return array.map { convertToNativeSwiftTypes($0) }
        } else if let string = object as? NSString {
            // Convert tab characters to spaces to avoid YAML formatting issues
            return String(string).replacingOccurrences(of: "\t", with: "    ")
        } else if let number = object as? NSNumber {
            // Check if it's a boolean
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            // Check if it's an integer
            if number === number.intValue as NSNumber {
                return number.intValue
            }
            // Otherwise treat as double
            return number.doubleValue
        } else if let date = object as? Date {
            // Convert Date to ISO8601 string format
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        } else {
            return object
        }
    }
    
    private func getDirectoriesToProcess() -> [String] {
        if manifestsOnly {
            return ["manifests"]
        } else if pkginfoOnly {
            return ["pkgsinfo"]
        } else {
            return ["manifests", "pkgsinfo"]
        }
    }
    
    private func processDirectory(_ directoryURL: URL, stats: inout MigrationStats, backup: Bool) throws {
        if verbose {
            print("Processing directory: \(directoryURL.path)")
        }
        
        // Create top-level backup directory if backup is enabled
        var backupRootURL: URL?
        if backup {
            let directoryName = directoryURL.lastPathComponent
            backupRootURL = directoryURL.deletingLastPathComponent().appendingPathComponent("\(directoryName).backup")
            try FileManager.default.createDirectory(at: backupRootURL!, withIntermediateDirectories: true, attributes: nil)
            if verbose {
                print("Created backup root directory: \(backupRootURL!.path)")
            }
        }
        
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        guard let fileEnumerator = enumerator else {
            throw YamlMigrateError.directoryError("Could not enumerate directory: \(directoryURL.path)")
        }
        
        for case let fileURL as URL in fileEnumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    // Check if it's a plist file (.plist extension) or a manifest file (in manifests directory)
                    let isManifestDirectory = directoryURL.path.contains("/manifests")
                    let isPlistFile = fileURL.pathExtension.lowercased() == "plist"
                    let isManifestFile = isManifestDirectory && !fileURL.lastPathComponent.hasPrefix(".") && !fileURL.lastPathComponent.hasSuffix(".backup") && !fileURL.lastPathComponent.hasSuffix(".yaml")
                    
                    if isPlistFile || isManifestFile {
                        try processFile(fileURL, stats: &stats, backup: backup, backupRootURL: backupRootURL, originalRootURL: directoryURL)
                    }
                }
            } catch {
                if verbose {
                    print("Error processing \(fileURL.path): \(error)")
                }
                stats.errors += 1
            }
        }
    }
    
    private func processFile(_ fileURL: URL, stats: inout MigrationStats, backup: Bool, backupRootURL: URL?, originalRootURL: URL) throws {
        // Handle YAML file naming - for files with .plist extension, replace with .yaml
        // For files without extension (manifests), just add .yaml
        let yamlURL: URL
        if fileURL.pathExtension.lowercased() == "plist" {
            yamlURL = fileURL.deletingPathExtension().appendingPathExtension("yaml")
        } else {
            yamlURL = fileURL.appendingPathExtension("yaml")
        }
        
        // Check if YAML file already exists
        if FileManager.default.fileExists(atPath: yamlURL.path) && !force {
            if verbose {
                print("YAML file already exists, skipping: \(yamlURL.path)")
            }
            stats.skipped += 1
            return
        }
        
        if verbose {
            print("Converting: \(fileURL.path) -> \(yamlURL.path)")
        }
        
        if dryRun {
            stats.processed += 1
            return
        }
        
        do {
            // Read the plist file
            let data = try Data(contentsOf: fileURL)
            let plistObject = try PropertyListSerialization.propertyList(
                from: data,
                options: .mutableContainers,
                format: nil
            )
            
            // Convert NSMutableDictionary/NSMutableArray to native Swift types
            let swiftObject = YamlMigrate.convertToNativeSwiftTypes(plistObject)
            
            // Convert to YAML with proper multi-line handling
            let yamlString = try formatYamlWithMultilineSupport(swiftObject)
            
            // Write YAML file
            try yamlString.write(to: yamlURL, atomically: true, encoding: String.Encoding.utf8)
            
            // Create backup if requested
            if backup, let backupRoot = backupRootURL {
                // Calculate relative path from original root to this file
                let relativePath = fileURL.path.replacingOccurrences(of: originalRootURL.path + "/", with: "")
                let backupFileURL = backupRoot.appendingPathComponent(relativePath)
                
                // Create intermediate directories in backup structure
                let backupDir = backupFileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true, attributes: nil)
                
                if !FileManager.default.fileExists(atPath: backupFileURL.path) {
                    try FileManager.default.copyItem(at: fileURL, to: backupFileURL)
                    if verbose {
                        print("Created backup: \(backupFileURL.path)")
                    }
                }
            }
            
            // Remove original plist file
            try FileManager.default.removeItem(at: fileURL)
            
            stats.processed += 1
            
        } catch {
            if verbose {
                print("Error converting \(fileURL.path): \(error)")
            }
            stats.errors += 1
            throw YamlMigrateError.conversionError("Failed to convert \(fileURL.path): \(error)")
        }
    }
    
    /// Formats YAML with proper multi-line string support
    private func formatYamlWithMultilineSupport(_ object: Any) throws -> String {
        // First, process the object to identify and mark multi-line strings
        let processedObject = processMultilineStrings(object)
        
        // Use Yams to dump the processed object
        var yamlString = try Yams.dump(object: processedObject, 
                                     indent: 2,
                                     width: -1, 
                                     allowUnicode: true)
        
        // Post-process to convert marked strings to literal block scalars
        yamlString = convertToLiteralBlocks(yamlString)
        
        return yamlString
    }
    
    /// Processes object to identify multi-line strings and marks them for literal block formatting
    private func processMultilineStrings(_ object: Any) -> Any {
        if let dict = object as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dict {
                if let stringValue = value as? String, shouldUseLiteralBlock(for: stringValue, key: key) {
                    // Mark this string for literal block formatting
                    result[key] = "MULTILINE_LITERAL:" + stringValue
                } else {
                    result[key] = processMultilineStrings(value)
                }
            }
            return result
        } else if let array = object as? [Any] {
            return array.map { processMultilineStrings($0) }
        } else {
            return object
        }
    }
    
    /// Determines if a string should use literal block format
    private func shouldUseLiteralBlock(for string: String, key: String) -> Bool {
        // Common keys that contain scripts or multi-line content
        let scriptKeys = [
            "installcheck_script", "uninstallcheck_script", "preinstall_script", 
            "postinstall_script", "preuninstall_script", "postuninstall_script",
            "installer_choices_xml", "notes", "description", "display_name_localized"
        ]
        
        // Use literal block if:
        // 1. The key is known to contain scripts/multi-line content, OR
        // 2. The string contains newlines and is longer than 50 characters, OR
        // 3. The string contains shell script indicators, OR
        // 4. The string contains tab characters
        return scriptKeys.contains(key.lowercased()) ||
               (string.contains("\n") && string.count > 50) ||
               (string.contains("#!/") || string.contains(" && ") || string.contains(" || ") || 
                string.contains("if [") || string.contains("for ") || string.contains("while ")) ||
               string.contains("\t")
    }
    
    /// Converts marked strings to YAML literal block format
    private func convertToLiteralBlocks(_ yamlString: String) -> String {
        let lines = yamlString.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            if line.contains("MULTILINE_LITERAL:") {
                // Extract key and check if this is a multi-line quoted string
                if let colonIndex = line.firstIndex(of: ":") {
                    let keyPart = String(line[..<colonIndex])
                    let valuePart = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    
                    // Check if this is a multi-line quoted string (starts with quote but doesn't end with quote)
                    let isMultiLineQuoted = (valuePart.hasPrefix("'") && !valuePart.hasSuffix("'")) ||
                                          (valuePart.hasPrefix("\"") && !valuePart.hasSuffix("\""))
                    
                    if isMultiLineQuoted {
                        // Collect all lines until we find the closing quote
                        var fullContent = valuePart
                        i += 1
                        while i < lines.count {
                            let nextLine = lines[i]
                            fullContent += "\n" + nextLine
                            if (valuePart.hasPrefix("'") && nextLine.hasSuffix("'")) ||
                               (valuePart.hasPrefix("\"") && nextLine.hasSuffix("\"")) {
                                break
                            }
                            i += 1
                        }
                        
                        // Process the full multi-line content
                        let processedBlock = processMultiLineContent(keyPart: keyPart, content: fullContent)
                        result.append(contentsOf: processedBlock)
                    } else {
                        // Single line quoted string
                        let processedBlock = processSingleLineContent(keyPart: keyPart, content: valuePart)
                        result.append(contentsOf: processedBlock)
                    }
                } else {
                    result.append(line)
                }
            } else {
                result.append(line)
            }
            i += 1
        }
        
        return result.joined(separator: "\n")
    }
    
    /// Processes single-line quoted content with MULTILINE_LITERAL marker
    private func processSingleLineContent(keyPart: String, content: String) -> [String] {
        var processedContent = content
        
        // Remove quotes
        if (processedContent.hasPrefix("'") && processedContent.hasSuffix("'")) ||
           (processedContent.hasPrefix("\"") && processedContent.hasSuffix("\"")) {
            processedContent = String(processedContent.dropFirst().dropLast())
        }
        
        if processedContent.hasPrefix("MULTILINE_LITERAL:") {
            let actualContent = String(processedContent.dropFirst("MULTILINE_LITERAL:".count))
            let leadingWhitespace = keyPart.prefix(while: { $0.isWhitespace })
            
            var result = [keyPart + ": |"]
            
            // Unescape and split content
            let unescapedContent = actualContent.replacingOccurrences(of: "\\n", with: "\n")
                                              .replacingOccurrences(of: "\\\"", with: "\"")
                                              .replacingOccurrences(of: "\\'", with: "'")
                                              .replacingOccurrences(of: "\\\\", with: "\\")
                                              .replacingOccurrences(of: "\\t", with: "    ")
            
            let contentLines = unescapedContent.components(separatedBy: "\n")
            for contentLine in contentLines {
                result.append(leadingWhitespace + "  " + contentLine)
            }
            
            return result
        } else {
            return [keyPart + ": " + content]
        }
    }
    
    /// Processes multi-line quoted content with MULTILINE_LITERAL marker
    private func processMultiLineContent(keyPart: String, content: String) -> [String] {
        var processedContent = content
        
        // Remove outer quotes
        if (processedContent.hasPrefix("'") && processedContent.hasSuffix("'")) ||
           (processedContent.hasPrefix("\"") && processedContent.hasSuffix("\"")) {
            processedContent = String(processedContent.dropFirst().dropLast())
        }
        
        if processedContent.hasPrefix("MULTILINE_LITERAL:") {
            let actualContent = String(processedContent.dropFirst("MULTILINE_LITERAL:".count))
            let leadingWhitespace = keyPart.prefix(while: { $0.isWhitespace })
            
            var result = [keyPart + ": |"]
            
            // For multi-line content, split by actual newlines (not escaped ones)
            let contentLines = actualContent.components(separatedBy: "\n")
            for contentLine in contentLines {
                result.append(leadingWhitespace + "  " + contentLine)
            }
            
            return result
        } else {
            // Not a marked string, return as-is but reconstructed
            return [keyPart + ": " + content]
        }
    }
    
    /// Creates a literal block format for multi-line content
    private func createLiteralBlock(indent: String, key: String, content: String) -> String {
        var result = indent + key + ": |"
        
        // Unescape the content - convert \\n to actual newlines and remove quotes
        var cleanContent = content
        
        // Remove surrounding quotes if present
        if (cleanContent.hasPrefix("\"") && cleanContent.hasSuffix("\"")) ||
           (cleanContent.hasPrefix("'") && cleanContent.hasSuffix("'")) {
            cleanContent = String(cleanContent.dropFirst().dropLast())
        }
        
        // Unescape newlines and other escaped characters
        cleanContent = cleanContent.replacingOccurrences(of: "\\n", with: "\n")
                                   .replacingOccurrences(of: "\\\"", with: "\"")
                                   .replacingOccurrences(of: "\\'", with: "'")
                                   .replacingOccurrences(of: "\\\\", with: "\\")
                                   .replacingOccurrences(of: "\\t", with: "    ")
        
        // Process the content line by line
        let lines = cleanContent.components(separatedBy: "\n")
        for line in lines {
            result += "\n" + indent + "  " + line
        }
        
        return result
    }
    
    private func printSummary(_ stats: MigrationStats) {
        print("\nMigration Summary:")
        print("Files processed: \(stats.processed)")
        print("Files skipped: \(stats.skipped)")
        print("Errors: \(stats.errors)")
        
        if dryRun {
            print("\n(This was a dry run - no files were actually modified)")
        }
    }
}

struct MigrationStats {
    var processed = 0
    var skipped = 0
    var errors = 0
}

enum YamlMigrateError: Error, LocalizedError {
    case directoryError(String)
    case conversionError(String)
    
    var errorDescription: String? {
        switch self {
        case .directoryError(let message):
            return "Directory error: \(message)"
        case .conversionError(let message):
            return "Conversion error: \(message)"
        }
    }
}
