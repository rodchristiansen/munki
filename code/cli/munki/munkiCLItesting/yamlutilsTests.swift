//
//  yamlutilsTests.swift
//  munkiCLItesting
//

import Foundation
import Testing

struct YamlUtilsTests {
    /// Strings a YAML reader would take for a number, boolean or null must be
    /// quoted on the way out so they come back as the same strings.
    @Test func ambiguousScalarsRoundTripAsStrings() throws {
        let values = ["1.0", "6.10", "7922.170", "10", "0", "007", "1e3", "0x1A", "0o17", "1_000", ".5",
                      "true", "False", "yes", "NO", "on", "off", "y", "n", "null", "~", ".inf", ".nan", "1:30", " padded "]
        for value in values {
            let item: PlistDict = ["name": "Probe", "version": value, "installs": [["path": "/A", "type": "file", "CFBundleVersion": value]]]
            let text = try yamlToString(item)
            let back = try #require(try readData(Data(text.utf8), preferYaml: true) as? PlistDict)
            #expect(back["version"] as? String == value, "version \(value) came back as \(String(describing: back["version"])) from:\n\(text)")
            let installs = try #require(back["installs"] as? [PlistDict])
            #expect(installs[0]["CFBundleVersion"] as? String == value)
        }
    }

    @Test func ordinaryStringsStayPlain() throws {
        let item: PlistDict = ["name": "Probe", "version": "2026.08.31.0100", "display_name": "Probe App", "minimum_os_version": "14.2.1"]
        let text = try yamlToString(item)
        #expect(text.contains("version: 2026.08.31.0100"))
        #expect(text.contains("display_name: Probe App"))
        #expect(text.contains("minimum_os_version: 14.2.1"))
        #expect(!text.contains("'"))
    }

    @Test func numericLookingVersionsAreQuoted() throws {
        let item: PlistDict = ["name": "Probe", "version": "1.0"]
        let text = try yamlToString(item)
        #expect(text.contains("version: '1.0'"))
    }
}
