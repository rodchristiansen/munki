//
//  yamlutilsTests.swift
//  munkiCLItesting
//
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

import Foundation
import Testing

struct yamlFloatResolverTests {
    /// Trailing-zero version strings must survive parsing.
    /// Without the custom resolver, Yams parses `10.10` as Double 10.1,
    /// losing the trailing zero before normalization can recover it.
    @Test func trailingZeroVersionsSurvive() async throws {
        let yaml = """
        minimum_os_version: 10.10
        maximum_os_version: 11.20
        version: 1.0
        """
        let parsed = try #require(
            readYaml(fromString: yaml) as? [String: Any],
            "Could not parse YAML"
        )
        #expect(parsed["minimum_os_version"] as? String == "10.10")
        #expect(parsed["maximum_os_version"] as? String == "11.20")
        #expect(parsed["version"] as? String == "1.0")
    }

    /// Non-trailing-zero floats still parse as strings under the custom resolver.
    @Test func floatLikeVersionsParseAsStrings() async throws {
        let yaml = """
        minimum_os_version: 10.13
        version: 2.3
        another_version: 26.4
        """
        let parsed = try #require(
            readYaml(fromString: yaml) as? [String: Any],
            "Could not parse YAML"
        )
        #expect(parsed["minimum_os_version"] as? String == "10.13")
        #expect(parsed["version"] as? String == "2.3")
        #expect(parsed["another_version"] as? String == "26.4")
    }

    /// Bare integers on version-like keys are normalized to strings by normalizeYamlTypes.
    @Test func integerVersionsNormalizedToStrings() async throws {
        let yaml = """
        minimum_os_version: 14
        version: 10
        """
        let parsed = try #require(
            readYaml(fromString: yaml) as? [String: Any],
            "Could not parse YAML"
        )
        #expect(parsed["minimum_os_version"] as? String == "14")
        #expect(parsed["version"] as? String == "10")
    }

    /// Integer values on non-version-like keys must stay as integers.
    /// Processors and size comparisons need native int types.
    @Test func nonVersionIntegersStayInt() async throws {
        let yaml = """
        installer_item_size: 1024
        unattended_install: true
        optional: false
        """
        let parsed = try #require(
            readYaml(fromString: yaml) as? [String: Any],
            "Could not parse YAML"
        )
        #expect(parsed["installer_item_size"] as? Int == 1024)
        #expect(parsed["unattended_install"] as? Bool == true)
        #expect(parsed["optional"] as? Bool == false)
    }

    /// Explicitly quoted versions must also round-trip unchanged.
    @Test func quotedVersionsUnchanged() async throws {
        let yaml = """
        minimum_os_version: '10.10'
        version: "1.0"
        """
        let parsed = try #require(
            readYaml(fromString: yaml) as? [String: Any],
            "Could not parse YAML"
        )
        #expect(parsed["minimum_os_version"] as? String == "10.10")
        #expect(parsed["version"] as? String == "1.0")
    }

    /// Nested dicts (e.g., inside receipts or installs) must also preserve versions.
    @Test func nestedVersionsPreserved() async throws {
        let yaml = """
        name: TestApp
        version: 1.0
        receipts:
          - packageid: com.example.testapp
            version: 2.10
        installs:
          - type: application
            path: /Applications/TestApp.app
            CFBundleShortVersionString: 3.20
        """
        let parsed = try #require(
            readYaml(fromString: yaml) as? [String: Any],
            "Could not parse YAML"
        )
        #expect(parsed["version"] as? String == "1.0")

        let receipts = try #require(parsed["receipts"] as? [[String: Any]])
        #expect(receipts.first?["version"] as? String == "2.10")

        let installs = try #require(parsed["installs"] as? [[String: Any]])
        #expect(installs.first?["CFBundleShortVersionString"] as? String == "3.20")
    }
}

struct mixedFormatDetectionTests {
    /// Data that is a valid XML plist parses as a plist regardless of preference.
    @Test func plistDataParsesEitherWay() async throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>name</key>
            <string>TestApp</string>
        </dict>
        </plist>
        """
        let data = try #require(plist.data(using: .utf8))
        let plistFirst = try #require(readData(data) as? [String: Any])
        #expect(plistFirst["name"] as? String == "TestApp")
        let yamlFirst = try #require(readData(data, preferYaml: true) as? [String: Any])
        #expect(yamlFirst["name"] as? String == "TestApp")
    }

    /// Data that is YAML parses as YAML regardless of preference.
    @Test func yamlDataParsesEitherWay() async throws {
        let yaml = """
        name: TestApp
        catalogs:
          - testing
        """
        let data = try #require(yaml.data(using: .utf8))
        let plistFirst = try #require(readData(data) as? [String: Any])
        #expect(plistFirst["catalogs"] as? [String] == ["testing"])
        let yamlFirst = try #require(readData(data, preferYaml: true) as? [String: Any])
        #expect(yamlFirst["catalogs"] as? [String] == ["testing"])
    }

    /// Content sniffing recognizes the XML header and YAML key/value lines.
    @Test func contentHeuristics() async throws {
        #expect(isLikelyYamlContent("<?xml version=\"1.0\"?>\n<plist>") == false)
        #expect(isLikelyYamlContent("---\nname: TestApp") == true)
        #expect(isLikelyYamlContent("name: TestApp\nversion: '1.0'") == true)
    }
}

struct yamlWriterTests {
    /// Empty-string values must round-trip through YAML write + read.
    /// `sanitizeForYaml` must not drop string values that are empty, and the
    /// writer must emit them explicitly quoted (`key: ''`) so they parse back
    /// as empty strings, not null/missing.
    @Test func emptyStringValuesRoundTrip() async throws {
        let input: [String: Any] = [
            "name": "TestApp",
            "version": "1.0",
            "description": "",
            "blocking_applications": "",
            "notes": "non-empty",
            "receipts": [
                [
                    "packageid": "com.example.testapp",
                    "version": "1.0",
                    "filename": "",
                ] as [String: Any],
            ],
        ]

        let yamlString = try yamlToString(input)

        // The empty-string keys must be present in the written YAML.
        #expect(yamlString.contains("description:"),
                "description key was dropped from YAML output: \(yamlString)")
        #expect(yamlString.contains("blocking_applications:"),
                "blocking_applications key was dropped from YAML output: \(yamlString)")
        #expect(yamlString.contains("filename:"),
                "nested filename empty-string key was dropped: \(yamlString)")

        // And the emitted empty strings must be explicitly quoted so they
        // parse back as "" rather than null.
        #expect(yamlString.contains("description: ''") || yamlString.contains("description: \"\""),
                "description empty string was not quoted: \(yamlString)")
        #expect(yamlString.contains("blocking_applications: ''") || yamlString.contains("blocking_applications: \"\""),
                "blocking_applications empty string was not quoted: \(yamlString)")

        let parsed = try #require(
            readYaml(fromString: yamlString) as? [String: Any],
            "Could not re-parse YAML output"
        )
        #expect(parsed["description"] as? String == "",
                "description did not round-trip as empty string (got \(String(describing: parsed["description"])))")
        #expect(parsed["blocking_applications"] as? String == "",
                "blocking_applications did not round-trip as empty string (got \(String(describing: parsed["blocking_applications"])))")
        #expect(parsed["name"] as? String == "TestApp")
        #expect(parsed["notes"] as? String == "non-empty")

        let receipts = try #require(parsed["receipts"] as? [[String: Any]])
        #expect(receipts.first?["filename"] as? String == "",
                "nested filename empty string did not round-trip (got \(String(describing: receipts.first?["filename"])))")
    }

    /// Known script field keys always emit as literal block scalars (`|`),
    /// even when the content is short or single-line. Key-based detection wins.
    @Test func scriptFieldShortContentEmitsAsLiteralBlock() async throws {
        let pkginfo: [String: Any] = [
            "name": "TestApp",
            "version": "1.0",
            "preinstall_script": "echo hi",
        ]
        let output = try yamlToString(pkginfo)
        // A YAML literal block starts with `|` on the key line, followed by an
        // indented value line. Plain/quoted scalars would put the value on the
        // same line as the key.
        #expect(output.contains("preinstall_script: |"),
                "Expected literal block for preinstall_script, got:\n\(output)")
        #expect(!output.contains("preinstall_script: echo hi"),
                "Expected script value on a new line, not inline. Got:\n\(output)")
    }

    /// All known script field keys round-trip as literal blocks.
    /// Regression guard against accidental removal of entries from `scriptFieldKeys`.
    @Test func allKnownScriptFieldsEmitAsLiteralBlock() async throws {
        for key in scriptFieldKeys {
            let pkginfo: [String: Any] = [key: "exit 0"]
            let output = try yamlToString(pkginfo)
            #expect(output.contains("\(key): |"),
                    "Expected literal block for \(key), got:\n\(output)")
        }
    }

    /// A non-script field (`description`) must NOT emit as a literal block even
    /// when its content contains a shebang-looking prefix. This is the main
    /// false-positive the tightened heuristic is designed to prevent.
    @Test func descriptionWithShebangPrefixIsNotLiteralBlock() async throws {
        let pkginfo: [String: Any] = [
            "name": "TestApp",
            "description": "#!/bin/sh usage note for admins",
        ]
        let output = try yamlToString(pkginfo)
        // Single-line content on a non-script key must never become a literal block.
        #expect(!output.contains("description: |"),
                "Single-line description must not emit as literal block. Got:\n\(output)")
    }

    /// Short multi-line content on an arbitrary (non-script, non-prose) key with
    /// script-like tokens ("if ", indentation) must NOT trigger literal-block
    /// emission under the strict heuristic.
    @Test func shortMultilineNonScriptDoesNotBecomeLiteralBlock() async throws {
        let pkginfo: [String: Any] = [
            "name": "TestApp",
            // Short (< 80 chars) multi-line string with script-like tokens.
            // No shebang, so the heuristic treats it as folded prose, not a
            // literal script block.
            "release_notes": "line one\nif fixed: bug",
        ]
        let output = try yamlToString(pkginfo)
        #expect(!output.contains("release_notes: |"),
                "Short multi-line non-script value must not emit as literal. Got:\n\(output)")
    }

    /// A multi-line value with a shebang on an unknown key IS treated as a script
    /// (literal block). Shebang is the strongest content-based signal we keep.
    @Test func multilineWithShebangOnUnknownKeyUsesLiteralBlock() async throws {
        let pkginfo: [String: Any] = [
            "custom_script_field": "#!/bin/sh\necho hi\nexit 0",
        ]
        let output = try yamlToString(pkginfo)
        #expect(output.contains("custom_script_field: |"),
                "Multi-line shebang content should emit as literal. Got:\n\(output)")
    }

    /// Versions must be quoted on the way out, not just tolerated on the way in.
    /// Munki's own reader strips the float rule, but MunkiAdmin, mwa2, AutoPkg and
    /// any CI script use a standard resolver, where a plain `10.10` becomes 10.1.
    @Test func ambiguousScalarsQuotedOnWrite() async throws {
        let pkginfo: [String: Any] = [
            "name": "TestApp",
            "version": "126.0",
            "minimum_os_version": "10.10",
        ]
        let output = try yamlToString(pkginfo)
        #expect(output.contains("version: '126.0'"),
                "Float-looking version must be quoted. Got:\n\(output)")
        #expect(output.contains("minimum_os_version: '10.10'"),
                "Trailing-zero version must be quoted. Got:\n\(output)")
    }

    /// Quoting applies only to values that would resolve to a non-string type.
    /// Genuine Ints and Bools stay native, and scripts stay block scalars.
    @Test func unambiguousValuesLeftAlone() async throws {
        let pkginfo: [String: Any] = [
            "name": "TestApp",
            "installer_item_size": 1024,
            "unattended_install": true,
            "postinstall_script": "#!/bin/bash\nexit 0",
        ]
        let output = try yamlToString(pkginfo)
        #expect(output.contains("name: TestApp"))
        #expect(output.contains("installer_item_size: 1024"))
        #expect(output.contains("unattended_install: true"))
        #expect(output.contains("postinstall_script: |"))
    }

    /// pkginfo output leads with name, display_name, version and ends with _metadata.
    @Test func pkginfoKeyOrdering() async throws {
        let pkginfo: [String: Any] = [
            "_metadata": ["created_by": "test"],
            "catalogs": ["testing"],
            "version": "1.0",
            "name": "TestApp",
            "display_name": "Test App",
        ]
        let output = try yamlToString(pkginfo)
        let lines = output.components(separatedBy: "\n")
        #expect(lines[0] == "name: TestApp")
        #expect(lines[1] == "display_name: Test App")
        #expect(lines[2] == "version: '1.0'")
        #expect(lines.last { !$0.isEmpty }?.hasPrefix("  created_by") == true)
        let metadataIndex = try #require(lines.firstIndex(of: "_metadata:"))
        let catalogsIndex = try #require(lines.firstIndex(of: "catalogs:"))
        #expect(catalogsIndex < metadataIndex)
    }

    /// A top-level manifest keeps alphabetical key order; only entries inside
    /// conditional_items lead with `condition`.
    @Test func manifestConditionalItemOrdering() async throws {
        let manifest: [String: Any] = [
            "included_manifests": ["base"],
            "catalogs": ["production"],
            "conditional_items": [
                [
                    "managed_installs": ["ModernApp"],
                    "condition": "os_vers_major >= 14",
                ] as [String: Any],
            ],
        ]
        let output = try yamlToString(manifest)
        let lines = output.components(separatedBy: "\n")
        #expect(lines[0] == "catalogs:")
        let conditionLine = try #require(lines.first { $0.contains("condition:") })
        let installsLine = try #require(lines.first { $0.contains("managed_installs:") })
        #expect(lines.firstIndex(of: conditionLine)! < lines.firstIndex(of: installsLine)!)
    }

    /// Foundation types coming out of the plist reader serialize to plain YAML types.
    @Test func foundationValuesSerialize() async throws {
        let input: [String: Any] = [
            "name": "TestApp",
            "installed_size": NSNumber(value: 4096),
            "unattended_install": NSNumber(value: true),
            "installer_item_hash": NSString(string: "abc123"),
            "blocking_applications": NSNull(),
        ]
        let output = try yamlToString(input)
        #expect(output.contains("installed_size: 4096"))
        #expect(output.contains("unattended_install: true"))
        #expect(output.contains("installer_item_hash: abc123"))
        #expect(!output.contains("blocking_applications"))
    }
}
