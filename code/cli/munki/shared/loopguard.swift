//
//  loopguard.swift
//  munki
//
//  Install-loop detection and suppression.
//
//  A package that installs successfully and is immediately wanted again is
//  looping: its installs/receipts/installcheck criteria never match what the
//  installer lays down, or something keeps changing underneath it. Left alone
//  it reinstalls every run. This guard notices, pauses the item for a window
//  that grows with each repeat, records why the package keeps wanting to
//  install, and clears itself when the pkgsinfo changes.
//
//  History is rebuilt from the session log's events.jsonl when that exists and
//  from the ManagedInstallReport archives otherwise, so the guard works with or
//  without the session log; the session log reads from the guard, never the
//  reverse. Rules, windows and message wording are shared with the Windows
//  client so a looping device reads the same on every surface.
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

import CryptoKit
import Foundation

// MARK: - Trigger

/// Why the status check decided a package needs install. Captured on every
/// check and carried on the InstallInfo item so the install phase can record
/// it with the attempt, whether or not that happens in the same process.
struct InstallTrigger: Codable, Equatable {
    static let maxDetailLength = 300

    var reasonCode: String
    var detectionMethod: String
    var detail: String
    var installedVersion: String?

    /// Builds a trigger, flattening the detail; nil when there is nothing to say.
    static func from(reasonCode: String?, detectionMethod: String?, detail: String?, installedVersion: String? = nil) -> InstallTrigger? {
        let code = (reasonCode ?? "").trimmingCharacters(in: .whitespaces)
        let flat = flatten(detail ?? "")
        if code.isEmpty, flat.isEmpty { return nil }
        let version = (installedVersion ?? "").trimmingCharacters(in: .whitespaces)
        return InstallTrigger(
            reasonCode: code,
            detectionMethod: (detectionMethod ?? "").isEmpty ? "none" : detectionMethod!,
            detail: flat,
            installedVersion: version.isEmpty ? nil : version
        )
    }

    static func flatten(_ text: String) -> String {
        let joined = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        if joined.count > maxDetailLength {
            return String(joined.prefix(maxDetailLength)) + "…"
        }
        return joined
    }

    var key: String { "\(reasonCode)|\(detectionMethod)|\(detail)" }

    func describe() -> String {
        if !detail.isEmpty { return detail }
        if !reasonCode.isEmpty { return reasonCode }
        return "an unnamed check"
    }

    /// Plist shape used on InstallInfo items.
    var plist: PlistDict {
        var d: PlistDict = ["reason_code": reasonCode, "detection_method": detectionMethod, "detail": detail]
        if let installedVersion { d["installed_version"] = installedVersion }
        return d
    }

    init(reasonCode: String, detectionMethod: String, detail: String, installedVersion: String?) {
        self.reasonCode = reasonCode
        self.detectionMethod = detectionMethod
        self.detail = detail
        self.installedVersion = installedVersion
    }

    init?(plist: PlistDict?) {
        guard let plist else { return nil }
        guard let t = InstallTrigger.from(
            reasonCode: plist["reason_code"] as? String,
            detectionMethod: plist["detection_method"] as? String,
            detail: plist["detail"] as? String,
            installedVersion: plist["installed_version"] as? String
        ) else { return nil }
        self = t
    }
}

// MARK: - State

struct PackageLoopState: Codable {
    var packageName: String
    var attemptCount = 0
    var sessionCount = 0
    var lastAttempt: Date?
    var lastVersion = ""
    var catalogFingerprint = ""
    var lastSuccess = false
    var suppressedUntil: Date?
    var suppressionReason = ""
    var versionAttempts = [String: Int]()
    var recentTimestamps = [Date]()
    var processedSessions = [String]()
    var suppressionCycles = 0
    var clearedAt: Date?
    var pendingRestartSince: Date?
    var trigger: InstallTrigger?
    var triggerLastSeen: Date?
    var triggerCounts = [String: Int]()

    init(packageName: String) {
        self.packageName = packageName
    }
}

struct LoopGuardState: Codable {
    var lastUpdated: Date?
    var clearedAt: Date?
    var packages = [String: PackageLoopState]()
}

/// On-disk wrapper, so state.json can grow other sections later.
struct LoopGuardStateFile: Codable {
    var loopGuard: LoopGuardState
}

/// One entry of reports/loop_suppressed.json and the LoopSuppressed report array.
struct LoopSuppressedReportItem: Codable {
    var packageName: String
    var version: String
    var reason: String
    var cause: String?
    var trigger: InstallTrigger?
    var triggerSummary: String?
    var suppressedUntil: Date?
    var pendingRestart: Bool
    var suppressionCycles: Int
    var attemptCount: Int
    var sessionCount: Int
    var clearCommand: String

    var plist: PlistDict {
        var d: PlistDict = [
            "package_name": packageName,
            "version": version,
            "reason": reason,
            "pending_restart": pendingRestart,
            "suppression_cycles": suppressionCycles,
            "attempt_count": attemptCount,
            "session_count": sessionCount,
            "clear_command": clearCommand,
        ]
        if let cause { d["cause"] = cause }
        if let trigger { d["trigger"] = trigger.plist }
        if let triggerSummary { d["trigger_summary"] = triggerSummary }
        if let suppressedUntil { d["suppressed_until"] = suppressedUntil }
        return d
    }
}

// MARK: - Guard

final class LoopGuard {
    /// Process-wide instance configured from preferences.
    static let shared: LoopGuard = {
        let enabled = boolPref("LoopGuardEnabled") ?? true
        let maxDays = intPref("LoopMaxTime") ?? defaultMaxSuppressionDays
        return LoopGuard(isBootstrap: pathExists(CHECKANDINSTALLATSTARTUPFLAG), disabled: !enabled, maxSuppressionDays: maxDays)
    }()

    /// The running client version, folded into every fingerprint so a client
    /// upgrade clears standing suppressions once. Set by managedsoftwareupdate
    /// at startup; tools that never install leave it empty.
    static var clientVersion = ""

    static let defaultMaxSuppressionDays = 7
    static let maxTrackedTriggers = 5
    static let recentTimestampsKept = 20
    static let historyWindowDays = 7
    static let bootTimeSkewTolerance: TimeInterval = 120

    let baseDir: String
    let isBootstrap: Bool
    let disabled: Bool
    let maxSuppressionDays: Int
    var now: () -> Date
    var bootTime: () -> Date

    private(set) var state = LoopGuardState()
    private var currentSessionId = ""
    private let lock = NSLock()

    init(baseDir: String? = nil, isBootstrap: Bool = false, disabled: Bool = false,
         maxSuppressionDays: Int = LoopGuard.defaultMaxSuppressionDays,
         now: @escaping () -> Date = Date.init,
         bootTime: @escaping () -> Date = LoopGuard.systemBootTime)
    {
        self.baseDir = baseDir ?? managedInstallsDir()
        self.isBootstrap = isBootstrap
        self.disabled = disabled
        self.maxSuppressionDays = maxSuppressionDays > 0 ? maxSuppressionDays : LoopGuard.defaultMaxSuppressionDays
        self.now = now
        self.bootTime = bootTime
        loadState()
        buildHistoryFromEvents()
        buildHistoryFromArchives()
    }

    var logsDir: String { (baseDir as NSString).appendingPathComponent("logs") }
    var reportsDir: String { (baseDir as NSString).appendingPathComponent("reports") }
    var statePath: String { (reportsDir as NSString).appendingPathComponent("state.json") }
    var suppressedReportPath: String { (reportsDir as NSString).appendingPathComponent("loop_suppressed.json") }
    var archivesDir: String { (baseDir as NSString).appendingPathComponent("Archives") }
    var cacheDir: String { (baseDir as NSString).appendingPathComponent("Cache") }

    // MARK: Fingerprints

    /// SHA256 of the concatenated fields, first 16 hex characters.
    static func computeFingerprint(_ fieldsConcat: String) -> String {
        let digest = SHA256.hash(data: Data(fieldsConcat.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// Fingerprint of everything in a pkginfo that decides whether and how an
    /// item installs. A server-stamped loop_fingerprint wins when present. The
    /// running munki version is folded in so a client upgrade clears standing
    /// suppressions once.
    static func catalogFingerprint(for pkginfo: PlistDict) -> String {
        if let stamped = pkginfo["loop_fingerprint"] as? String, !stamped.trimmingCharacters(in: .whitespaces).isEmpty {
            return computeFingerprint("\(stamped)|\(clientVersion)")
        }
        var parts = [String]()
        for key in ["version", "installcheck_script", "version_script", "preinstall_script", "postinstall_script",
                    "uninstall_script", "installer_item_hash", "installer_item_location", "installer_type", "uninstall_method"]
        {
            parts.append(pkginfo.stringValue(forKey: key) ?? "")
        }
        for item in pkginfo["installs"] as? [PlistDict] ?? [] {
            let type = item["type"] as? String ?? ""
            let path = item["path"] as? String ?? ""
            let md5 = item["md5checksum"] as? String ?? ""
            let version = item.stringValue(forKey: item["version_comparison_key"] as? String ?? "CFBundleShortVersionString") ?? ""
            let bundleID = item["CFBundleIdentifier"] as? String ?? ""
            parts.append("\(type):\(path):\(md5):\(version):\(bundleID);")
        }
        for receipt in pkginfo["receipts"] as? [PlistDict] ?? [] {
            parts.append("\(receipt["packageid"] as? String ?? ""):\(receipt.stringValue(forKey: "version") ?? "");")
        }
        parts.append(clientVersion)
        return computeFingerprint(parts.joined(separator: "|"))
    }

    /// The subset of a pkginfo the install phase needs to re-run the status
    /// check after an install, carried on the InstallInfo item as loop_check.
    static func checkInfo(for pkginfo: PlistDict) -> PlistDict {
        var info = PlistDict()
        for key in ["name", "version", "installs", "receipts", "installcheck_script", "version_script",
                    "installer_type", "OnDemand", "display_name"]
        {
            if let value = pkginfo[key] { info[key] = value }
        }
        return info
    }

    // MARK: Sessions

    /// Session id shape: yyyy-MM-dd-HHmm of the run start, the same id the
    /// session log gives a run, so history from either source lines up.
    static func sessionId(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f.string(from: date)
    }

    func setCurrentSession(startTime: Date) {
        setCurrentSession(id: LoopGuard.sessionId(for: startTime))
    }

    func setCurrentSession(id: String) {
        lock.lock(); defer { lock.unlock() }
        currentSessionId = id
    }

    // MARK: Gate

    /// Whether an install of `name` should be skipped this run, with the message to show.
    func shouldSuppress(name: String, version: String, catalogFingerprint: String? = nil, trigger: InstallTrigger? = nil) -> (suppress: Bool, reason: String) {
        if isBootstrap || disabled || name.isEmpty { return (false, "") }
        lock.lock(); defer { lock.unlock() }
        let key = name.lowercased()
        guard var pkg = state.packages[key] else { return (false, "") }
        noteTrigger(&pkg, trigger, countIt: false)

        let (changed, changeDetail) = detectCatalogChange(pkg, version: version, fingerprint: catalogFingerprint)
        if changed {
            resetLoopHistory(&pkg, version: version, fingerprint: catalogFingerprint)
            state.packages[key] = pkg
            saveState()
            return (false, "Auto-cleared: \(changeDetail)")
        }
        if let fingerprint = catalogFingerprint, !fingerprint.isEmpty, pkg.catalogFingerprint.isEmpty {
            pkg.catalogFingerprint = fingerprint
            state.packages[key] = pkg
            saveState()
        }
        if var until = pkg.suppressedUntil {
            if until == Date.distantFuture {
                until = (pkg.lastAttempt ?? now()).addingTimeInterval(TimeInterval(maxSuppressionDays * 86400))
                pkg.suppressedUntil = until
            }
            let remaining = until.timeIntervalSince(now())
            if remaining > 0 {
                let message = buildSuppressionMessage(pkg, version: version, remaining: remaining)
                state.packages[key] = pkg
                saveState()
                return (true, message)
            }
            let cycles = pkg.suppressionCycles + 1
            resetLoopHistory(&pkg, version: version, fingerprint: catalogFingerprint)
            pkg.suppressionCycles = cycles
            state.packages[key] = pkg
            saveState()
            return (false, "")
        }
        let result = evaluateSuppressionThresholds(&pkg, version: version)
        state.packages[key] = pkg
        saveState()
        return result
    }

    /// The second line of a loop warning: what the package's own checks keep finding.
    func suppressionCause(name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let pkg = state.packages[name.lowercased()] else { return nil }
        return "Needs install because " + describeTrigger(pkg)
    }

    // MARK: Recording

    func recordAttempt(name: String, version: String, success: Bool, catalogFingerprint: String? = nil,
                       selfReportedWarning: Bool = false, trigger: InstallTrigger? = nil)
    {
        if disabled || selfReportedWarning || name.isEmpty { return }
        lock.lock(); defer { lock.unlock() }
        let key = name.lowercased()
        var pkg = state.packages[key] ?? PackageLoopState(packageName: name)
        let stamp = now()
        pkg.attemptCount += 1
        pkg.lastAttempt = stamp
        noteTrigger(&pkg, trigger, countIt: true)
        if !currentSessionId.isEmpty, !pkg.processedSessions.contains(currentSessionId) {
            pkg.processedSessions.append(currentSessionId)
        }
        pkg.sessionCount = pkg.processedSessions.count
        pkg.lastVersion = version
        pkg.lastSuccess = success
        if let fingerprint = catalogFingerprint, !fingerprint.isEmpty {
            pkg.catalogFingerprint = fingerprint
        }
        pkg.versionAttempts[version, default: 0] += 1
        pkg.recentTimestamps.append(stamp)
        if pkg.recentTimestamps.count > LoopGuard.recentTimestampsKept {
            pkg.recentTimestamps.removeFirst(pkg.recentTimestamps.count - LoopGuard.recentTimestampsKept)
        }
        _ = evaluateSuppressionThresholds(&pkg, version: version)
        state.packages[key] = pkg
        saveState()
    }

    @discardableResult
    func clearLoop(name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let key = name.lowercased()
        guard var pkg = state.packages[key] else { return false }
        resetLoopHistory(&pkg, version: "", fingerprint: nil)
        state.packages[key] = pkg
        saveState()
        return true
    }

    @discardableResult
    func clearAll() -> Int {
        lock.lock(); defer { lock.unlock() }
        let count = state.packages.values.filter { $0.suppressedUntil != nil }.count
        state = LoopGuardState()
        state.clearedAt = now()
        saveState()
        return count
    }

    // MARK: Pending restart

    func recordPendingRestart(name: String, version: String, catalogFingerprint: String? = nil) {
        if disabled || isBootstrap || name.isEmpty { return }
        lock.lock(); defer { lock.unlock() }
        let key = name.lowercased()
        var pkg = state.packages[key] ?? PackageLoopState(packageName: name)
        pkg.pendingRestartSince = now()
        pkg.lastVersion = version
        if let fingerprint = catalogFingerprint, !fingerprint.isEmpty { pkg.catalogFingerprint = fingerprint }
        state.packages[key] = pkg
        saveState()
    }

    func shouldDeferForRestart(name: String, catalogFingerprint: String? = nil) -> (defer: Bool, reason: String) {
        if isBootstrap || disabled || name.isEmpty { return (false, "") }
        lock.lock(); defer { lock.unlock() }
        let key = name.lowercased()
        guard var pkg = state.packages[key], let since = pkg.pendingRestartSince else { return (false, "") }
        func clear() -> (Bool, String) {
            pkg.pendingRestartSince = nil
            state.packages[key] = pkg
            saveState()
            return (false, "")
        }
        if let fingerprint = catalogFingerprint, !fingerprint.isEmpty, !pkg.catalogFingerprint.isEmpty, fingerprint != pkg.catalogFingerprint {
            return clear()
        }
        let boot = bootTime()
        if boot.addingTimeInterval(-LoopGuard.bootTimeSkewTolerance) > since {
            return clear()
        }
        if now().timeIntervalSince(since) > TimeInterval(maxSuppressionDays * 86400) {
            return clear()
        }
        let versionText = pkg.lastVersion.isEmpty ? "" : " v\(pkg.lastVersion)"
        return (true, "Pending restart: \(pkg.packageName)\(versionText) installed successfully and is finalized by a reboot — reinstall deferred until the machine restarts")
    }

    // MARK: Convergence

    static let nonConvergenceReason = "installcheck still reported action needed immediately after a successful install"

    @discardableResult
    func markNonConverged(name: String, version: String, catalogFingerprint: String? = nil, reprobeHours: Int = 24, trigger: InstallTrigger? = nil) -> String {
        let reason = LoopGuard.nonConvergenceReason
        if disabled || name.isEmpty { return reason }
        lock.lock(); defer { lock.unlock() }
        let hours = min(reprobeHours > 0 ? reprobeHours : 24, maxSuppressionDays * 24)
        let key = name.lowercased()
        var pkg = state.packages[key] ?? PackageLoopState(packageName: name)
        pkg.suppressedUntil = now().addingTimeInterval(TimeInterval(hours * 3600))
        pkg.suppressionReason = reason
        pkg.lastVersion = version
        noteTrigger(&pkg, trigger, countIt: false)
        if let fingerprint = catalogFingerprint, !fingerprint.isEmpty { pkg.catalogFingerprint = fingerprint }
        state.packages[key] = pkg
        saveState()
        return reason
    }

    // MARK: Reporting

    func suppressedPackages() -> [(name: String, reason: String, suppressedUntil: Date?)] {
        lock.lock(); defer { lock.unlock() }
        return state.packages.values
            .filter { isActive($0) }
            .sorted { $0.packageName.lowercased() < $1.packageName.lowercased() }
            .map { ($0.packageName, $0.suppressionReason, $0.suppressedUntil) }
    }

    func suppressedReport() -> [LoopSuppressedReportItem] {
        lock.lock(); defer { lock.unlock() }
        return state.packages.values
            .filter { isActive($0) || $0.pendingRestartSince != nil }
            .sorted { $0.packageName.lowercased() < $1.packageName.lowercased() }
            .map { pkg in
                let pending = !isActive(pkg) && pkg.pendingRestartSince != nil
                let remaining = (pkg.suppressedUntil ?? now()).timeIntervalSince(now())
                return LoopSuppressedReportItem(
                    packageName: pkg.packageName,
                    version: pkg.lastVersion,
                    reason: pending ? "pending restart" : buildSuppressionMessage(pkg, version: pkg.lastVersion, remaining: max(remaining, 0)),
                    cause: pending ? nil : "Needs install because " + describeTrigger(pkg),
                    trigger: pkg.trigger,
                    triggerSummary: pkg.trigger?.describe(),
                    suppressedUntil: pkg.suppressedUntil == Date.distantFuture ? nil : pkg.suppressedUntil,
                    pendingRestart: pending,
                    suppressionCycles: pkg.suppressionCycles,
                    attemptCount: pkg.attemptCount,
                    sessionCount: pkg.sessionCount,
                    clearCommand: "managedsoftwareupdate --clear-loop \(pkg.packageName)"
                )
            }
    }

    /// Writes reports/loop_suppressed.json and returns the same list for the
    /// caller to put on the run report.
    @discardableResult
    func writeReports() -> [LoopSuppressedReportItem] {
        let items = suppressedReport()
        ensureReportsDir()
        if let data = try? LoopGuard.encoder.encode(items) {
            try? data.write(to: URL(fileURLWithPath: suppressedReportPath), options: .atomic)
        }
        return items
    }

    func packageState(name: String) -> PackageLoopState? {
        lock.lock(); defer { lock.unlock() }
        return state.packages[name.lowercased()]
    }

    func checkCacheForPackage(name: String) -> (hasCache: Bool, cachePath: String?) {
        let fm = FileManager.default
        let dir = (cacheDir as NSString).appendingPathComponent(name)
        if let entries = try? fm.contentsOfDirectory(atPath: dir), let first = entries.sorted().first {
            return (true, (dir as NSString).appendingPathComponent(first))
        }
        if let entries = try? fm.contentsOfDirectory(atPath: cacheDir) {
            // installer items are cached as Name.ext or Name-version.ext
            let prefixes = [name.lowercased() + ".", name.lowercased() + "-"]
            if let match = entries.sorted().first(where: { entry in prefixes.contains { entry.lowercased().hasPrefix($0) } }) {
                return (true, (cacheDir as NSString).appendingPathComponent(match))
            }
        }
        return (false, nil)
    }

    func diagnosticInfo(name: String) -> String {
        guard let pkg = packageState(name: name) else { return "\(name): no loop history" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        var lines = ["\(pkg.packageName):"]
        lines.append("  Attempts: \(pkg.attemptCount) across \(pkg.sessionCount) sessions")
        lines.append("  Last version: \(pkg.lastVersion.isEmpty ? "(unknown)" : pkg.lastVersion)")
        lines.append("  Catalog fingerprint: \(pkg.catalogFingerprint.isEmpty ? "(none)" : pkg.catalogFingerprint)")
        lines.append("  Suppression cycles served: \(pkg.suppressionCycles)")
        lines.append("  Last attempt: \(pkg.lastAttempt.map { f.string(from: $0) } ?? "never")")
        lines.append("  Last success: \(pkg.lastSuccess)")
        if !pkg.versionAttempts.isEmpty {
            let versions = pkg.versionAttempts.sorted { $0.key < $1.key }.map { "\($0.key) (\($0.value)x)" }.joined(separator: ", ")
            lines.append("  Versions attempted: \(versions)")
        }
        lines.append("  Needs install because \(describeTrigger(pkg))")
        if let seen = pkg.triggerLastSeen { lines.append("  Trigger last seen: \(f.string(from: seen))") }
        let cache = checkCacheForPackage(name: pkg.packageName)
        if cache.hasCache {
            lines.append("  Cache: HIT — \(cache.cachePath ?? "")")
            lines.append("  Diagnosis: Loop is install/status-check issue, not download (cached installer exists)")
        } else {
            lines.append("  Cache: MISS — package not cached")
        }
        if let until = pkg.suppressedUntil {
            lines.append("  Suppressed until: \(until == Date.distantFuture ? "indefinite" : f.string(from: until))")
            lines.append("  Reason: \(pkg.suppressionReason)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Rules

    private func isActive(_ pkg: PackageLoopState) -> Bool {
        guard let until = pkg.suppressedUntil else { return false }
        return until == Date.distantFuture || until > now()
    }

    private func detectCatalogChange(_ pkg: PackageLoopState, version: String, fingerprint: String?) -> (Bool, String) {
        if let fingerprint, !fingerprint.isEmpty, !pkg.catalogFingerprint.isEmpty, fingerprint != pkg.catalogFingerprint {
            if !version.isEmpty, !pkg.lastVersion.isEmpty, version != pkg.lastVersion {
                return (true, "catalog changed (version \(pkg.lastVersion) → \(version))")
            }
            return (true, "catalog changed (pkgsinfo fields updated, same version \(version.isEmpty ? pkg.lastVersion : version))")
        }
        if (fingerprint ?? "").isEmpty || pkg.catalogFingerprint.isEmpty,
           !version.isEmpty, !pkg.lastVersion.isEmpty, version != pkg.lastVersion
        {
            return (true, "catalog version changed from \(pkg.lastVersion) to \(version)")
        }
        return (false, "")
    }

    private func resetLoopHistory(_ pkg: inout PackageLoopState, version: String, fingerprint: String?) {
        pkg.suppressedUntil = nil
        pkg.suppressionReason = ""
        pkg.attemptCount = 0
        pkg.sessionCount = 0
        pkg.suppressionCycles = 0
        pkg.versionAttempts = [:]
        pkg.recentTimestamps = []
        pkg.processedSessions = []
        pkg.triggerCounts = [:]
        pkg.trigger = nil
        pkg.triggerLastSeen = nil
        pkg.pendingRestartSince = nil
        pkg.clearedAt = now()
        if !version.isEmpty { pkg.lastVersion = version }
        if let fingerprint, !fingerprint.isEmpty { pkg.catalogFingerprint = fingerprint }
    }

    private func noteTrigger(_ pkg: inout PackageLoopState, _ trigger: InstallTrigger?, countIt: Bool) {
        guard let trigger else { return }
        pkg.trigger = trigger
        pkg.triggerLastSeen = now()
        guard countIt else { return }
        if pkg.triggerCounts[trigger.key] == nil, pkg.triggerCounts.count >= LoopGuard.maxTrackedTriggers { return }
        pkg.triggerCounts[trigger.key, default: 0] += 1
    }

    private func describeTrigger(_ pkg: PackageLoopState) -> String {
        guard let trigger = pkg.trigger else {
            return "the cause was not recorded yet — it is captured on the next check"
        }
        let total = pkg.triggerCounts.values.reduce(0, +)
        let detail = trigger.describe()
        if pkg.triggerCounts.count == 1, total >= 2 {
            return "\(detail) [\(trigger.reasonCode), unchanged over all \(total) attempts]"
        }
        if pkg.triggerCounts.count > 1 {
            let summary = pkg.triggerCounts
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .map { "\($0.key.split(separator: "|").first.map(String.init) ?? $0.key) x\($0.value)" }
                .joined(separator: ", ")
            return "\(detail) [most recent of \(total) attempts: \(summary)]"
        }
        if trigger.reasonCode.isEmpty { return detail }
        return "\(detail) [\(trigger.reasonCode)]"
    }

    private func evaluateSuppressionThresholds(_ pkg: inout PackageLoopState, version: String) -> (Bool, String) {
        let current = now()
        let recent = pkg.recentTimestamps.filter { current.timeIntervalSince($0) <= 2 * 3600 }.count
        if recent >= 3 {
            return suppress(&pkg, version: version, window: 12 * 3600, reason: "\(recent) installs within 2 hours")
        }
        let versionCount = pkg.versionAttempts[version] ?? 0
        if versionCount >= 3, pkg.sessionCount >= 3 {
            let window: TimeInterval = versionCount >= 8 ? maxWindow : (versionCount >= 5 ? 24 * 3600 : 6 * 3600)
            return suppress(&pkg, version: version, window: window,
                            reason: "installed \(versionCount) times across \(pkg.sessionCount) sessions")
        }
        let distinctVersions = pkg.versionAttempts.count
        let loopAttempts = distinctVersions > 1 ? pkg.attemptCount - (distinctVersions - 1) : pkg.attemptCount
        if loopAttempts >= 8, pkg.sessionCount >= 5 {
            return suppress(&pkg, version: version, window: maxWindow,
                            reason: "\(pkg.attemptCount) installs across \(pkg.sessionCount) sessions")
        }
        if loopAttempts >= 5, pkg.sessionCount >= 4 {
            return suppress(&pkg, version: version, window: 24 * 3600,
                            reason: "\(pkg.attemptCount) installs across \(pkg.sessionCount) sessions")
        }
        return (false, "")
    }

    private var maxWindow: TimeInterval { TimeInterval(maxSuppressionDays * 86400) }

    private func suppress(_ pkg: inout PackageLoopState, version: String, window: TimeInterval, reason: String) -> (Bool, String) {
        var effectiveWindow = window
        var effectiveReason = reason
        let floor: TimeInterval = pkg.suppressionCycles >= 2 ? maxWindow : (pkg.suppressionCycles == 1 ? 24 * 3600 : 0)
        if floor > effectiveWindow {
            effectiveWindow = floor
            effectiveReason += " — escalated to \(LoopGuard.formatDuration(effectiveWindow)) after \(pkg.suppressionCycles) prior suppression window(s)"
        }
        pkg.suppressedUntil = now().addingTimeInterval(effectiveWindow)
        pkg.suppressionReason = effectiveReason
        return (true, buildSuppressionMessage(pkg, version: version, remaining: effectiveWindow))
    }

    private func buildSuppressionMessage(_ pkg: PackageLoopState, version: String, remaining: TimeInterval) -> String {
        let shownVersion = version.isEmpty ? pkg.lastVersion : version
        let versionText = shownVersion.isEmpty ? "" : " v\(shownVersion)"
        let rule = pkg.suppressionReason.isEmpty ? "repeated installs" : pkg.suppressionReason
        return "Looping install detected: \(pkg.packageName)\(versionText) — \(rule); paused for \(LoopGuard.formatDuration(remaining))"
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if total >= 86400 { return "\(days)d \(hours)h" }
        if total >= 3600 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: - History rebuild

    /// Folds one historical install attempt into the package state. Attempts in
    /// a session already processed are skipped; attempts older than the clear
    /// watermark are seen but not counted, which is what makes a clear stick
    /// across rebuilds.
    private func absorbHistoricalAttempt(name: String, version: String, time: Date, success: Bool, sessionId: String) {
        let key = name.lowercased()
        var pkg = state.packages[key] ?? PackageLoopState(packageName: name)
        let watermark = [state.clearedAt, pkg.clearedAt].compactMap { $0 }.max()
        let preClear = watermark.map { time < $0 } ?? false
        if !pkg.processedSessions.contains(sessionId) {
            if !preClear {
                pkg.attemptCount += 1
                pkg.versionAttempts[version, default: 0] += 1
                pkg.recentTimestamps.append(time)
                if pkg.lastAttempt == nil || time > pkg.lastAttempt! {
                    pkg.lastAttempt = time
                    pkg.lastVersion = version
                    pkg.lastSuccess = success
                }
            }
            pkg.processedSessions.append(sessionId)
        }
        pkg.sessionCount = pkg.processedSessions.count
        if pkg.recentTimestamps.count > LoopGuard.recentTimestampsKept {
            pkg.recentTimestamps.sort()
            pkg.recentTimestamps.removeFirst(pkg.recentTimestamps.count - LoopGuard.recentTimestampsKept)
        }
        state.packages[key] = pkg
    }

    private var historyCutoff: Date { now().addingTimeInterval(-TimeInterval(LoopGuard.historyWindowDays * 86400)) }

    /// Rebuilds attempt history from the session log's day-nested
    /// logs/yyyy-MM-dd/HHmm/events.jsonl files: every completed or failed
    /// install event, with its own timestamp and session id.
    private func buildHistoryFromEvents() {
        let fm = FileManager.default
        guard let days = try? fm.contentsOfDirectory(atPath: logsDir) else { return }
        let cutoff = historyCutoff
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone.current
        dayFormatter.dateFormat = "yyyy-MM-dd"
        for day in days.sorted() {
            guard let dayDate = dayFormatter.date(from: day) else { continue }
            if dayDate.addingTimeInterval(86400) < cutoff { continue }
            let dayDir = (logsDir as NSString).appendingPathComponent(day)
            guard let sessions = try? fm.contentsOfDirectory(atPath: dayDir) else { continue }
            for session in sessions.sorted() {
                let path = ((dayDir as NSString).appendingPathComponent(session) as NSString).appendingPathComponent("events.jsonl")
                guard let data = fm.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") {
                    guard let event = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
                    guard event["event_type"] as? String == "install", event["action"] as? String == "install" else { continue }
                    let status = event["status"] as? String ?? ""
                    guard status == "completed" || status == "failed" else { continue }
                    guard let name = event["package_name"] as? String, !name.isEmpty else { continue }
                    guard let time = LoopGuard.parseTimestamp(event["timestamp"] as? String), time >= cutoff else { continue }
                    let sessionId = event["session_id"] as? String ?? "\(day)-\(session)"
                    absorbHistoricalAttempt(name: name, version: event["package_version"] as? String ?? "",
                                            time: time, success: status == "completed", sessionId: sessionId)
                }
            }
        }
    }

    /// Rebuilds attempt history from archived ManagedInstallReports, for
    /// sessions the events rebuild did not cover.
    private func buildHistoryFromArchives() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: archivesDir) else { return }
        let cutoff = historyCutoff
        for entry in entries.sorted() where entry.hasPrefix("ManagedInstallReport-") && entry.hasSuffix(".plist") {
            let path = (archivesDir as NSString).appendingPathComponent(entry)
            guard let report = (try? readPlist(fromFile: path)) as? PlistDict else { continue }
            let startTime = (report["StartTime"] as? Date) ?? LoopGuard.dateFromArchiveName(entry)
            guard let startTime, startTime >= cutoff else { continue }
            let sessionId = LoopGuard.sessionId(for: startTime)
            for result in report["InstallResults"] as? [PlistDict] ?? [] {
                guard let name = result["name"] as? String, !name.isEmpty else { continue }
                if result["applesus"] as? Bool ?? false { continue }
                absorbHistoricalAttempt(name: name, version: result["version"] as? String ?? "",
                                        time: (result["time"] as? Date) ?? startTime,
                                        success: (result["status"] as? Int ?? 0) == 0, sessionId: sessionId)
            }
        }
    }

    static func parseTimestamp(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    static func dateFromArchiveName(_ name: String) -> Date? {
        let stem = name.replacingOccurrences(of: "ManagedInstallReport-", with: "").replacingOccurrences(of: ".plist", with: "")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.date(from: stem)
    }

    // MARK: - Persistence

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func loadState() {
        guard let data = FileManager.default.contents(atPath: statePath) else { return }
        if let wrapped = try? LoopGuard.decoder.decode(LoopGuardStateFile.self, from: data) {
            state = wrapped.loopGuard
            return
        }
        if let bare = try? LoopGuard.decoder.decode(LoopGuardState.self, from: data), !bare.packages.isEmpty {
            state = bare
            return
        }
        state = LoopGuardState()
    }

    private func ensureReportsDir() {
        if !pathExists(reportsDir) {
            try? FileManager.default.createDirectory(atPath: reportsDir, withIntermediateDirectories: true)
        }
    }

    private func saveState() {
        state.lastUpdated = now()
        ensureReportsDir()
        guard let data = try? LoopGuard.encoder.encode(LoopGuardStateFile(loopGuard: state)) else { return }
        try? data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
    }

    // MARK: - Boot time

    static func systemBootTime() -> Date {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, 2, &tv, &size, nil, 0) == 0 {
            return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
        }
        return Date.distantPast
    }
}
