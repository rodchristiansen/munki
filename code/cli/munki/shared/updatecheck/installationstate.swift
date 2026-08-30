//
//  installationstate.swift
//  munki
//
//  Created by Greg Neagle on 8/19/24.
//  Copyright 2024-2026 The Munki Project. All rights reserved.
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

private let display = DisplayAndLog.main

enum InstallationState: Int {
    case thisVersionNotInstalled = 0
    case thisVersionInstalled = 1
    case newerVersionInstalled = 2
}

/// Reason codes for a status check result.
enum StatusReasonCode {
    static let notInstalled = "not_installed"
    static let versionOutdated = "version_outdated"
    static let versionMismatch = "version_mismatch"
    static let fileMissing = "file_missing"
    static let hashMismatch = "hash_mismatch"
    static let receiptMissing = "receipt_missing"
    static let installcheckNeeded = "installcheck_needed"
    static let onDemand = "on_demand"
    static let versionMatch = "version_match"
    static let newerInstalled = "newer_installed"
    static let checkFailed = "check_failed"
}

/// How a status check reached its answer.
enum DetectionMethod {
    static let script = "script"
    static let versionScript = "version_script"
    static let installsArray = "installs_array"
    static let receipts = "receipts"
    static let osVersion = "os_version"
    static let none = "none"
}

/// The outcome of deciding whether an item needs install, with the reason the
/// decision was made so the reason can be recorded, shown and compared across
/// runs.
struct InstallStatusResult {
    var state: InstallationState
    var reasonCode: String
    var detectionMethod: String
    var detail: String
    var installedVersion: String?

    var needsAction: Bool { state == .thisVersionNotInstalled }

    var trigger: InstallTrigger? {
        InstallTrigger.from(reasonCode: reasonCode, detectionMethod: detectionMethod, detail: detail, installedVersion: installedVersion)
    }
}

/// Reads the version an installs item currently has on disk, or nil when the
/// item is absent or has no version metadata.
private func installedVersionOfInstallsItem(_ item: PlistDict) -> String? {
    guard let type = item["type"] as? String, let path = item["path"] as? String, pathExists(path) else { return nil }
    let key = item["version_comparison_key"] as? String ?? "CFBundleShortVersionString"
    switch type {
    case "application", "bundle":
        let version = getBundleVersion(path, key: key)
        return version.isEmpty ? nil : version
    case "plist":
        if let plist = (try? readPlist(fromFile: path)) as? PlistDict, let version = plist.stringValue(forKey: key) {
            return version
        }
        return nil
    default:
        return nil
    }
}

/// Describes one installs entry the way the trigger detail names it:
/// "installs[i] type path".
private func describeInstallsItem(_ item: PlistDict, index: Int) -> String {
    let type = item["type"] as? String ?? "untyped"
    let identity = item["path"] as? String ?? item["CFBundleIdentifier"] as? String ?? item["CFBundleName"] as? String ?? ""
    return "installs[\(index)] \(type) \(identity)".trimmingCharacters(in: .whitespaces)
}

/// Turns a comparison result for an installs entry into a reason code and detail.
private func installsItemFinding(_ item: PlistDict, index: Int, result: MunkiComparisonResult, catalogVersion: String) -> (code: String, detail: String, installedVersion: String?) {
    let whereText = describeInstallsItem(item, index: index)
    let type = item["type"] as? String ?? ""
    switch result {
    case .notPresent:
        return (StatusReasonCode.fileMissing, "\(whereText): not present", nil)
    case .older:
        if type == "file", let expected = item["md5checksum"] as? String {
            let found = (item["path"] as? String).map { md5hash(file: $0) } ?? ""
            return (StatusReasonCode.hashMismatch, "\(whereText): hash mismatch — expected \(expected), found \(found)", nil)
        }
        let key = item["version_comparison_key"] as? String ?? "CFBundleShortVersionString"
        let wanted = item.stringValue(forKey: key) ?? catalogVersion
        let found = installedVersionOfInstallsItem(item)
        if let found {
            return (StatusReasonCode.versionOutdated, "\(whereText): \(key) \(found) is older than the catalog's \(wanted)", found)
        }
        return (StatusReasonCode.versionOutdated, "\(whereText): installed version is older than the catalog's \(wanted)", nil)
    default:
        return (StatusReasonCode.versionMismatch, "\(whereText): does not match the catalog", installedVersionOfInstallsItem(item))
    }
}

/// Checks to see if the item described by pkginfo (or a newer version) is
/// currently installed, and says why it decided so.
///
/// All tests must pass to be considered installed.
func installStatus(_ pkginfo: PlistDict) async -> InstallStatusResult {
    let name = pkginfo["name"] as? String ?? "<unknown>"
    let version = pkginfo.stringValue(forKey: "version") ?? ""
    var foundNewer = false
    var newerVersion: String?

    func installed(_ method: String, _ detail: String) -> InstallStatusResult {
        if foundNewer {
            return InstallStatusResult(state: .newerVersionInstalled, reasonCode: StatusReasonCode.newerInstalled,
                                       detectionMethod: method, detail: "A newer version of \(name) than \(version) is installed", installedVersion: newerVersion)
        }
        return InstallStatusResult(state: .thisVersionInstalled, reasonCode: StatusReasonCode.versionMatch,
                                   detectionMethod: method, detail: detail, installedVersion: version)
    }

    if pkginfo["OnDemand"] as? Bool ?? false {
        // we always need to install these items
        display.debug1("This is an OnDemand item. Must install.")
        return InstallStatusResult(state: .thisVersionNotInstalled, reasonCode: StatusReasonCode.onDemand,
                                   detectionMethod: DetectionMethod.none, detail: "\(name) is an OnDemand item", installedVersion: nil)
    }
    if pkginfo["installcheck_script"] is String {
        let results = await runEmbeddedScriptAndReturnResults(
            name: "installcheck_script",
            pkginfo: pkginfo,
            suppressError: true
        )
        display.debug1("installcheck_script returned \(results.exitcode)")
        // retcode 0 means install IS needed
        if results.exitcode == 0 {
            let output = (results.output + "\n" + results.error).trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = output.isEmpty ? "installcheck_script exited 0" : "installcheck_script exited 0: \(output)"
            return InstallStatusResult(state: .thisVersionNotInstalled, reasonCode: StatusReasonCode.installcheckNeeded,
                                       detectionMethod: DetectionMethod.script, detail: detail, installedVersion: nil)
        }
        // non-zero could be an error or successfully indicating
        // that an install is not needed. We hope it's the latter.
        // return .thisVersionInstalled so we're marked as not needing to be installed
        return InstallStatusResult(state: .thisVersionInstalled, reasonCode: StatusReasonCode.versionMatch,
                                   detectionMethod: DetectionMethod.script, detail: "installcheck_script exited \(results.exitcode)", installedVersion: nil)
    }
    if pkginfo["version_script"] is String {
        // if a version_script is defined, use that to determine installedState
        let compareResult = await compareUsingVersionScript(pkginfo)
        switch compareResult {
        case .notPresent:
            return InstallStatusResult(state: .thisVersionNotInstalled, reasonCode: StatusReasonCode.notInstalled,
                                       detectionMethod: DetectionMethod.versionScript, detail: "version_script reported \(name) is not present", installedVersion: nil)
        case .older:
            return InstallStatusResult(state: .thisVersionNotInstalled, reasonCode: StatusReasonCode.versionOutdated,
                                       detectionMethod: DetectionMethod.versionScript, detail: "version_script reported a version older than the catalog's \(version)", installedVersion: nil)
        case .newer:
            return InstallStatusResult(state: .newerVersionInstalled, reasonCode: StatusReasonCode.newerInstalled,
                                       detectionMethod: DetectionMethod.versionScript, detail: "version_script reported a version newer than \(version)", installedVersion: nil)
        case .same:
            return InstallStatusResult(state: .thisVersionInstalled, reasonCode: StatusReasonCode.versionMatch,
                                       detectionMethod: DetectionMethod.versionScript, detail: "version_script reported \(version)", installedVersion: version)
        }
    }
    let installerType = pkginfo["installer_type"] as? String ?? ""
    if installerType == "startosinstall",
       var installerItemVersion = pkginfo.stringValue(forKey: "version")
    {
        let currentOSVersion = getOSVersion() // just gets major.minor
        let installerVersionParts = installerItemVersion.components(separatedBy: ".")
        if (Int(installerVersionParts[0]) ?? 0) > 10 {
            // if we're running Big Sur+, we just want the major (11, 12, etc)
            installerItemVersion = installerVersionParts[0]
        } else {
            // need just major.minor part of the version -- 10.12 and not 10.12.4
            installerItemVersion = installerVersionParts[0] + "." + installerVersionParts[1]
        }
        let compareResult = compareVersions(currentOSVersion, installerItemVersion)
        if compareResult == .older {
            return InstallStatusResult(state: .thisVersionNotInstalled, reasonCode: StatusReasonCode.versionOutdated,
                                       detectionMethod: DetectionMethod.osVersion, detail: "macOS \(currentOSVersion) is older than \(installerItemVersion)", installedVersion: currentOSVersion)
        }
        if compareResult == .newer {
            return InstallStatusResult(state: .newerVersionInstalled, reasonCode: StatusReasonCode.newerInstalled,
                                       detectionMethod: DetectionMethod.osVersion, detail: "macOS \(currentOSVersion) is newer than \(installerItemVersion)", installedVersion: currentOSVersion)
        }
        return InstallStatusResult(state: .thisVersionInstalled, reasonCode: StatusReasonCode.versionMatch,
                                   detectionMethod: DetectionMethod.osVersion, detail: "macOS \(currentOSVersion) is installed", installedVersion: currentOSVersion)
    }
    if installerType == "stage_os_installer",
       var installerItemVersion = pkginfo.stringValue(forKey: "version")
    {
        // we return .newerVersionInstalled if the installed macOS is the same version
        // or higher than the version of this item
        // we return .thisVersionInstalled if the OS installer has already been staged
        // otherwise return .thisVersionNotInstalled
        let currentOSVersion = getOSVersion() // just gets major.minor
        let installerVersionParts = installerItemVersion.components(separatedBy: ".")
        if (Int(installerVersionParts[0]) ?? 0) > 10 {
            // if we're running Big Sur+, we just want the major (11, 12, etc)
            installerItemVersion = installerVersionParts[0]
        } else {
            // need just major.minor part of the version -- 10.12 and not 10.12.4
            installerItemVersion = installerVersionParts[0] + "." + installerVersionParts[1]
        }
        let compareResult = compareVersions(currentOSVersion, installerItemVersion)
        if compareResult == .same || compareResult == .newer {
            return InstallStatusResult(state: .newerVersionInstalled, reasonCode: StatusReasonCode.newerInstalled,
                                       detectionMethod: DetectionMethod.osVersion, detail: "macOS \(currentOSVersion) is at or above \(installerItemVersion)", installedVersion: currentOSVersion)
        }
        // installed OS version is lower; check to see if we've staged the os installer
        for (index, item) in (pkginfo["installs"] as? [PlistDict] ?? []).enumerated() {
            do {
                let compareResult = try compareItem(item)
                if compareResult != .same {
                    let finding = installsItemFinding(item, index: index, result: compareResult, catalogVersion: version)
                    return InstallStatusResult(state: .thisVersionNotInstalled, reasonCode: finding.code,
                                               detectionMethod: DetectionMethod.installsArray, detail: finding.detail, installedVersion: finding.installedVersion)
                }
            } catch {
                display.error(error.localizedDescription)
                // return .thisVersionInstalled so we don't attempt an install
                return InstallStatusResult(state: .thisVersionInstalled, reasonCode: StatusReasonCode.checkFailed,
                                           detectionMethod: DetectionMethod.installsArray, detail: error.localizedDescription, installedVersion: nil)
            }
        }
        // all items are present and same version
        return installed(DetectionMethod.installsArray, "the staged OS installer is present")
    }
    // do we have installs items?
    if let installItems = pkginfo["installs"] as? [PlistDict],
       !installItems.isEmpty
    {
        for (index, item) in installItems.enumerated() {
            do {
                let compareResult = try compareItem(item)
                if compareResult == .older || compareResult == .notPresent {
                    let finding = installsItemFinding(item, index: index, result: compareResult, catalogVersion: version)
                    return InstallStatusResult(state: .thisVersionNotInstalled, reasonCode: finding.code,
                                               detectionMethod: DetectionMethod.installsArray, detail: finding.detail, installedVersion: finding.installedVersion)
                }
                if compareResult == .newer {
                    foundNewer = true
                    newerVersion = installedVersionOfInstallsItem(item)
                }
            } catch {
                display.error(error.localizedDescription)
                // return .thisVersionInstalled so we don't attempt an install
                return InstallStatusResult(state: .thisVersionInstalled, reasonCode: StatusReasonCode.checkFailed,
                                           detectionMethod: DetectionMethod.installsArray, detail: error.localizedDescription, installedVersion: nil)
            }
        }
        return installed(DetectionMethod.installsArray, "all installs items are present at \(version)")
    } else if let receipts = pkginfo["receipts"] as? [PlistDict] {
        // if there are no 'installs' items, then we'll use receipt info
        // to determine install status.
        for item in receipts {
            do {
                let compareResult = try await compareReceipt(item)
                let pkgid = item["packageid"] as? String ?? "<unknown>"
                let wanted = item.stringValue(forKey: "version") ?? version
                if compareResult == .notPresent {
                    return InstallStatusResult(state: .thisVersionNotInstalled, reasonCode: StatusReasonCode.receiptMissing,
                                               detectionMethod: DetectionMethod.receipts, detail: "receipt \(pkgid) is not present", installedVersion: nil)
                }
                if compareResult == .older {
                    let installedPkgs = await getInstalledPackages()
                    let found = installedPkgs[pkgid]
                    let detail = found.map { "receipt \(pkgid) \($0) is older than the catalog's \(wanted)" } ?? "receipt \(pkgid) is older than the catalog's \(wanted)"
                    return InstallStatusResult(state: .thisVersionNotInstalled, reasonCode: StatusReasonCode.versionOutdated,
                                               detectionMethod: DetectionMethod.receipts, detail: detail, installedVersion: found)
                }
                if compareResult == .newer {
                    foundNewer = true
                }
            } catch {
                display.error(error.localizedDescription)
                // return .thisVersionInstalled so we don't attempt an install
                return InstallStatusResult(state: .thisVersionInstalled, reasonCode: StatusReasonCode.checkFailed,
                                           detectionMethod: DetectionMethod.receipts, detail: error.localizedDescription, installedVersion: nil)
            }
        }
        return installed(DetectionMethod.receipts, "all receipts are present at \(version)")
    }
    // if we got this far, we passed all the tests, so the item
    // must be installed (or we don't have enough info...)
    return installed(DetectionMethod.none, "no installs, receipts or installcheck_script to test; assumed installed")
}

/// Checks to see if the item described by pkginfo (or a newer version) is
/// currently installed
///
/// All tests must pass to be considered installed.
/// Returns InstallationState
func installedState(_ pkginfo: PlistDict) async -> InstallationState {
    return await installStatus(pkginfo).state
}

/// Checks to see if some version of a pkgitem is installed.
func someVersionInstalled(_ pkginfo: PlistDict) async -> Bool {
    if pkginfo["OnDemand"] as? Bool ?? false {
        // These should never be counted as installed
        display.debug1("This is an OnDemand item.")
        return false
    }
    if pkginfo["installcheck_script"] is String {
        // installcheck_script can really only tell us that an item needs
        // to be installed, or it doesn't.
        // it can't tell us that an older version of the item is installed
        let retcode = await runEmbeddedScript(
            name: "installcheck_script",
            pkginfo: pkginfo,
            suppressError: true
        )
        display.debug1("installcheck_script returned \(retcode)")
        // retcode 0 means install is needed
        // (ie, item is not installed)
        // non-zero could be an error or successfully indicating
        // that an install is not needed. We hope it's the latter.
        return retcode != 0
    }
    if pkginfo["version_script"] is String {
        // if there's a version_script, let's use that to determine
        // if some version installed
        let comparisonResult = await compareUsingVersionScript(pkginfo)
        if comparisonResult == .notPresent {
            return false
        }
        return true
    }
    if let installerType = pkginfo["installer_type"] as? String,
       installerType == "startosinstall" || installerType == "stage_os_installer"
    {
        // Some version of macOS is always installed!
        return true
    }
    // do we have installs items?
    if let installItems = pkginfo["installs"] as? [PlistDict],
       !installItems.isEmpty
    {
        for item in installItems {
            do {
                let compareResult = try compareItem(item)
                if compareResult == .notPresent {
                    return false
                }
            } catch {
                display.error(error.localizedDescription)
                return false
            }
        }
    } else if let receipts = pkginfo["receipts"] as? [PlistDict] {
        for item in receipts {
            do {
                let compareResult = try await compareReceipt(item)
                if compareResult == .notPresent {
                    return false
                }

            } catch {
                display.error(error.localizedDescription)
                // return .thisVersionInstalled so we don't attempt an install
                return false
            }
        }
    }
    // if we got this far, we passed all the tests, so the item
    // must be installed (or we don't have enough info...)
    return true
}

/// Checks to see if there is any evidence that the item described
/// by pkginfo (any version) is currently installed.
/// If any tests pass, the item might be installed.
/// This is used when determining if we can remove the item, thus
/// the attention given to the uninstall method.
func evidenceThisIsInstalled(_ pkginfo: PlistDict) async -> Bool {
    if pkginfo["OnDemand"] as? Bool ?? false {
        // These should never be counted as installed
        display.debug1("This is an OnDemand item.")
        return false
    }
    if pkginfo["uninstallcheck_script"] is String {
        // installcheck_script can really only tell us that an item needs
        // to be installed, or it doesn't.
        // it can't tell us that an older version of the item is installed
        let retcode = await runEmbeddedScript(
            name: "uninstallcheck_script",
            pkginfo: pkginfo,
            suppressError: true
        )
        display.debug1("uninstallcheck_script returned \(retcode)")
        // retcode 0 means uninstall is needed
        // (ie, item is installed)
        // non-zero could be an error or successfully indicating
        // that an uninstall is not needed.
        return retcode == 0
    }
    if pkginfo["installcheck_script"] is String {
        // installcheck_script can really only tell us that an item needs
        // to be installed, or it doesn't.
        // it can't tell us that an older version of the item is installed
        let retcode = await runEmbeddedScript(
            name: "installcheck_script",
            pkginfo: pkginfo,
            suppressError: true
        )
        display.debug1("installcheck_script returned \(retcode)")
        // retcode 0 means install is needed
        // (ie, item is not installed)
        // non-zero could be an error or successfully indicating
        // that an install is not needed. We hope it's the latter.
        return retcode != 0
    }
    if pkginfo["version_script"] is String {
        // if a comparison using a version_script returns anything
        // other than .notPresent that's evidence the item is installed
        let comparisonResult = await compareUsingVersionScript(pkginfo)
        if comparisonResult != .notPresent {
            return true
        }
    }
    if let installerType = pkginfo["installer_type"] as? String,
       installerType == "startosinstall" || installerType == "stage_os_installer"
    {
        // Some version of macOS is always installed!
        return true
    }
    var foundAllInstallItems = false
    if let installItems = pkginfo["installs"] as? [PlistDict],
       !installItems.isEmpty,
       (pkginfo["uninstall_method"] as? String ?? "") != "removepackages"
    {
        display.debug2("Checking 'installs' items...")
        foundAllInstallItems = true
        for item in installItems {
            if let path = item["path"] as? String, !pathExists(path) {
                // this item isn't present
                display.debug2("\(path) not found on disk.")
                foundAllInstallItems = false
            }
        }
        if foundAllInstallItems {
            display.debug2("Found all installs items")
            return true
        }
    }
    if let itemName = pkginfo["name"] as? String,
       let receipts = pkginfo["receipts"] as? [PlistDict],
       !receipts.isEmpty
    {
        display.debug2("Checking receipts...")
        let pkgdata = await analyzeInstalledPkgs()

        if let installedNames = pkgdata["installed_names"] as? [String],
           installedNames.contains(itemName)
        {
            display.debug2("Found matching receipts")
            return true
        }
        display.debug2("Installed receipts don't match for \(itemName)")
    }
    // if we got this far, we failed all the tests, so the item
    // must not be installed (or we don't have the right info...)
    return false
}
