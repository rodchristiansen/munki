//
//  yamlutils.swift
//  munki
//
//  Created by Rod Christiansen on 10/5/25.
//
//  Copyright 2025 The Munki Project
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
//
//  This file is the only place the Swift tools depend on Yams
//  (https://github.com/jpsim/Yams) for YAML parsing and serialization. Yams and
//  the libYAML C library it bundles are both MIT-licensed, which is compatible
//  with Munki's Apache License 2.0; their notices are reproduced in the
//  repository NOTICE file. Yams has no third-party Swift dependencies of its own
//  and is pinned to an exact release. Because the dependency is confined to this
//  file, the pinned MIT source could be vendored in-tree with no other code
//  changes should the package ever be abandoned or withdrawn.

import Foundation
import Yams

enum YamlError: Error {
    case readError(description: String)
    case writeError(description: String)
}

extension YamlError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .readError(description):
            return description
        case let .writeError(description):
            return description
        }
    }
}

// MARK: - Type-Flexible String Extraction

/// Extract a string value from a dictionary, handling multiple YAML types.
/// This allows clean YAML files without quote requirements for version-like values.
///
/// YAML parsers may interpret unquoted values differently:
///   - `version: 10.13` → Double (10.13)
///   - `version: 2025.12.25.1308` → String (multiple dots)
///   - `version: '10.13'` → String
///   - `version: 14` → Int
///
/// This function handles all cases by trying String first, then converting
/// numeric types to strings with appropriate formatting.
///
/// Usage:
///   ```swift
///   // Instead of: item["minimum_os_version"] as? String
///   // Use: yamlStringValue(from: item, forKey: "minimum_os_version")
///   ```
func yamlStringValue(from dict: [String: Any], forKey key: String) -> String? {
    guard let value = dict[key] else { return nil }

    // Try String first (most common case)
    if let stringValue = value as? String {
        return stringValue.isEmpty ? nil : stringValue
    }

    // Handle Double (e.g., 10.13 parsed as float)
    if let doubleValue = value as? Double {
        // Format to remove trailing zeros: 14.0 -> "14", 10.12 -> "10.12"
        return String(format: "%.10g", doubleValue)
    }

    // Handle Int (e.g., version: 14)
    if let intValue = value as? Int {
        return String(intValue)
    }

    // Handle Bool (unlikely for versions but be safe)
    if let boolValue = value as? Bool {
        return String(boolValue)
    }

    // Fallback: try to convert using String(describing:)
    let described = String(describing: value)
    return described.isEmpty ? nil : described
}

/// Convenience extension on Dictionary for cleaner syntax
extension Dictionary where Key == String, Value == Any {
    /// Get a string value, automatically converting numeric types to strings.
    /// This allows YAML files to omit quotes on version-like values.
    func stringValue(forKey key: String) -> String? {
        return yamlStringValue(from: self, forKey: key)
    }
}

// MARK: - Custom YAML Resolver

/// Resolver that treats float-looking scalars as strings.
///
/// Without this, Yams parses `minimum_os_version: 10.10` as Double 10.1, losing the
/// trailing zero before we can do anything about it. A post-parse fix-up can never
/// recover that information — "10.10" and "10.1" are distinct versions.
///
/// Removing the float rule means scalars like `10.10`, `2.3`, `1.0`, `26.4` resolve
/// to `.str` and arrive as Swift Strings, preserving the author's exact text.
/// Integer and boolean resolvers are kept intact so `installed_size: 1024`,
/// `optional: yes`, etc. still parse as their native types.
///
/// This matches the approach used by AutoPkg's AutoPkgYAMLLoader.
private let munkiYamlResolver = Resolver.default.removing(.float)

// MARK: - Reading

/// Check if a file path has a YAML extension
func isYamlFile(_ filepath: String) -> Bool {
    let fileExtension = (filepath as NSString).pathExtension.lowercased()
    return fileExtension == "yaml" || fileExtension == "yml"
}

/// Attempt to read YAML from a file
func readYaml(fromFile filepath: String) throws -> Any? {
    do {
        let yamlString = try String(contentsOfFile: filepath, encoding: .utf8)
        let parsed = try Yams.load(yaml: yamlString, munkiYamlResolver)
        return normalizeYamlTypes(parsed)
    } catch {
        throw YamlError.readError(description: "Failed to read YAML from \(filepath): \(error)")
    }
}

/// Attempt to read YAML from data
func readYaml(fromData data: Data) throws -> Any? {
    guard let yamlString = String(data: data, encoding: .utf8) else {
        throw YamlError.readError(description: "Data is not valid UTF-8")
    }
    do {
        let parsed = try Yams.load(yaml: yamlString, munkiYamlResolver)
        return normalizeYamlTypes(parsed)
    } catch {
        throw YamlError.readError(description: "Failed to parse YAML data: \(error)")
    }
}

/// Attempt to read YAML from a string
func readYaml(fromString string: String) throws -> Any? {
    do {
        let parsed = try Yams.load(yaml: string, munkiYamlResolver)
        return normalizeYamlTypes(parsed)
    } catch {
        throw YamlError.readError(description: "Failed to parse YAML string: \(error)")
    }
}

/// Normalize YAML parsed data to ensure version-like fields are strings.
///
/// With `munkiYamlResolver` in place, float-looking scalars (10.10, 2.3, 1.0) already
/// arrive as Strings and this pass is a no-op for them. This function still exists to
/// handle the Int case: `minimum_os_version: 14` parses as Int 14 under the default
/// int resolver (which we keep, since fields like `installed_size: 1024` need to stay
/// integer-typed). Without this pass, a later `as? String` cast on the int-typed
/// `minimum_os_version` would silently return nil and bypass the OS version check.
func normalizeYamlTypes(_ object: Any?) -> Any? {
    guard let object = object else { return nil }

    // Keys that YAML may parse as numeric but Munki expects as strings.
    // IMPORTANT: If you add a new version-like key to Munki's pkginfo schema,
    // add it here so unquoted values like `10.12` are coerced to "10.12"
    // instead of remaining as Double, which would fail `as? String` casts.
    let stringKeys: Set<String> = [
        "minimum_os_version",
        "maximum_os_version",
        "minimum_munki_version",
        "minimum_update_version",
        "version",
        "installer_item_version",
        "installed_version",
        "product_version",
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "minosversion",
    ]

    if let dict = object as? [String: Any] {
        var normalized: [String: Any] = [:]
        for (key, value) in dict {
            // Convert numeric values to strings for version-related keys
            if stringKeys.contains(key) {
                if let floatValue = value as? Double {
                    // Convert float to string, preserving precision
                    // Remove trailing zeros: 14.0 -> "14", 10.12 -> "10.12"
                    let formatted = String(format: "%.10g", floatValue)
                    normalized[key] = formatted
                } else if let intValue = value as? Int {
                    normalized[key] = String(intValue)
                } else if let stringValue = value as? String {
                    normalized[key] = stringValue
                } else {
                    normalized[key] = normalizeYamlTypes(value)
                }
            } else {
                normalized[key] = normalizeYamlTypes(value)
            }
        }
        return normalized
    } else if let array = object as? [Any] {
        return array.map { normalizeYamlTypes($0) }
    } else {
        return object
    }
}

// MARK: - File Format Detection for Mixed Repositories

/// Attempt to read a file that could be either plist or YAML format
/// Uses dual-parsing approach: tries preferred format first, falls back to other format
func readMixedFormatFile(fromFile filepath: String, preferYaml: Bool = false) throws -> Any? {
    let data = try Data(contentsOf: URL(fileURLWithPath: filepath))
    return try readData(data, preferYaml: preferYaml, filepath: filepath)
}

/// Reads YAML from data, but only accepts a dictionary or array result.
///
/// Almost any text is a valid YAML document: an XML plist parses as a single
/// multi-line plain scalar. Manifests, pkginfo and catalogs are always
/// dictionaries or arrays, so a scalar result means the data was not YAML
/// and the plist parser should get its turn.
private func readYamlContainer(fromData data: Data) throws -> Any {
    let parsed = try readYaml(fromData: data)
    if let dict = parsed as? [String: Any] {
        return dict
    }
    if let array = parsed as? [Any] {
        return array
    }
    throw YamlError.readError(description: "YAML document is not a dictionary or array")
}

/// Attempt to read data that could be either plist or YAML format
/// Uses dual-parsing approach: tries preferred format first, falls back to other format
func readData(_ data: Data, preferYaml: Bool = false, filepath: String? = nil) throws -> Any? {
    let fileDescription = filepath ?? "data"

    if preferYaml {
        // Try YAML first, fallback to plist
        do {
            return try readYamlContainer(fromData: data)
        } catch {
            // YAML failed, try plist
            do {
                return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            } catch let plistError {
                throw YamlError.readError(description: "Failed to parse \(fileDescription) as YAML or plist. YAML error: \(error). Plist error: \(plistError)")
            }
        }
    } else {
        // Try plist first, fallback to YAML
        do {
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            // Plist failed, try YAML
            do {
                return try readYamlContainer(fromData: data)
            } catch let yamlError {
                throw YamlError.readError(description: "Failed to parse \(fileDescription) as plist or YAML. Plist error: \(error). YAML error: \(yamlError)")
            }
        }
    }
}

/// Detect if file content is likely YAML based on content analysis
/// This is a heuristic check that looks for YAML-specific patterns
func isLikelyYamlContent(_ content: String) -> Bool {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

    // Check for YAML document separator
    if trimmed.hasPrefix("---") {
        return true
    }

    // Check for XML/plist header
    if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<plist") {
        return false
    }

    // Look for YAML-style key-value patterns (key: value)
    // This is a simple heuristic - YAML uses colons for key-value separation
    let lines = content.components(separatedBy: .newlines).prefix(10)
    var yamlLikeLines = 0
    var xmlLikeLines = 0

    for line in lines {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
            continue // Skip empty lines and comments
        }

        // YAML patterns
        if trimmedLine.contains(":") && !trimmedLine.hasPrefix("<") {
            yamlLikeLines += 1
        }

        // XML/plist patterns
        if trimmedLine.hasPrefix("<") && trimmedLine.hasSuffix(">") {
            xmlLikeLines += 1
        }
    }

    // If we see more YAML-like patterns than XML-like, probably YAML
    return yamlLikeLines > xmlLikeLines
}

/// Smart content-based format detection for files without extensions
/// Reads file content and uses heuristics to determine format, then parses accordingly
func detectFileContent(fromFile filepath: String, preferYaml: Bool = false) throws -> Any? {
    let content = try String(contentsOfFile: filepath, encoding: .utf8)
    let likelyYaml = isLikelyYamlContent(content)

    // Use content detection to influence parsing preference
    let shouldTryYamlFirst = preferYaml || likelyYaml

    let data = content.data(using: .utf8) ?? Data()
    return try readData(data, preferYaml: shouldTryYamlFirst, filepath: filepath)
}
