//
//  yaml_to_plist.swift
//  yaml_to_plist
//
//  Created for MunkiAdmin YAML support
//  Converts a YAML file to plist format for MunkiAdmin compatibility
//

import Foundation
import Yams

struct YamlToPlist {
    static func main() {
        // Get command line arguments
        let args = CommandLine.arguments
        
        guard args.count >= 2 else {
            print("Usage: yaml_to_plist <yaml_file_path>")
            exit(1)
        }
        
        let yamlFilePath = args[1]
        let yamlURL = URL(fileURLWithPath: yamlFilePath)
        
        do {
            // Read YAML file
            let yamlData = try Data(contentsOf: yamlURL)
            let yamlString = String(data: yamlData, encoding: .utf8) ?? ""
            
            // Parse YAML to Swift object
            let yamlObject = try Yams.load(yaml: yamlString)
            
            // Convert to native Swift types (similar to our migration tool)
            let swiftObject = convertToNativeSwiftTypes(yamlObject)
            
            // Convert to plist format
            let plistData = try PropertyListSerialization.data(fromPropertyList: swiftObject, 
                                                             format: .xml, 
                                                             options: 0)
            
            // Output plist data to stdout
            FileHandle.standardOutput.write(plistData)
            
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    
    private static func convertToNativeSwiftTypes(_ object: Any?) -> Any {
        if let dict = object as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = convertToNativeSwiftTypes(value)
            }
            return result
        } else if let array = object as? [Any] {
            return array.map { convertToNativeSwiftTypes($0) }
        } else if let string = object as? String {
            return string
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
        } else if let bool = object as? Bool {
            return bool
        } else if let int = object as? Int {
            return int
        } else if let double = object as? Double {
            return double
        } else if let date = object as? Date {
            return date
        } else if object == nil {
            return NSNull()
        } else {
            // For any other type, try to preserve it as-is
            return object ?? NSNull()
        }
    }
}

// Run the main function
YamlToPlist.main()
