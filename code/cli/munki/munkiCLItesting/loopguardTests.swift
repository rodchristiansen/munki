//
//  loopguardTests.swift
//  munkiCLItesting
//

import Foundation
import Testing

final class LoopGuardTests {
    private func makeTempRoot() -> String {
        let root = NSTemporaryDirectory() + "loopguard-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    /// A guard with a controllable clock and no bootstrap flag.
    private func makeGuard(_ root: String, disabled: Bool = false, bootstrap: Bool = false, maxDays: Int = 7) -> LoopGuard {
        let clock = Clock()
        let g = LoopGuard(baseDir: root, isBootstrap: bootstrap, disabled: disabled, maxSuppressionDays: maxDays,
                          now: { clock.now }, bootTime: { clock.boot })
        clocks[ObjectIdentifier(g)] = clock
        return g
    }

    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var boot = Date(timeIntervalSince1970: 1_799_000_000)
    }

    private var clocks = [ObjectIdentifier: Clock]()

    private func clock(_ g: LoopGuard) -> Clock { clocks[ObjectIdentifier(g)]! }

    private let trigger = InstallTrigger.from(
        reasonCode: "version_outdated", detectionMethod: "installs_array",
        detail: "installs[0] application /Applications/Foo.app: CFBundleShortVersionString 1.0 is older than the catalog's 1.1",
        installedVersion: "1.0"
    )!

    /// Records `count` attempts, each in its own session, one minute apart.
    private func attempts(_ g: LoopGuard, name: String = "Foo", version: String = "1.1", count: Int, spacing: TimeInterval = 60, trigger: InstallTrigger? = nil) {
        for i in 0 ..< count {
            g.setCurrentSession(id: "2026-08-30-\(String(format: "%04d", i))")
            g.recordAttempt(name: name, version: version, success: true, catalogFingerprint: "fp1", trigger: trigger)
            clock(g).now = clock(g).now.addingTimeInterval(spacing)
        }
    }

    @Test func newGuardSuppressesNothing() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        #expect(g.shouldSuppress(name: "Foo", version: "1.0").suppress == false)
        #expect(g.shouldSuppress(name: "", version: "1.0").suppress == false)
        #expect(g.suppressedPackages().isEmpty)
    }

    @Test func rapidFireThreeInstallsWithinTwoHoursSuppressesForTwelveHours() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        attempts(g, count: 3, trigger: trigger)
        let result = g.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1", trigger: trigger)
        #expect(result.suppress)
        #expect(result.reason.hasPrefix("Looping install detected: Foo v1.1 — 3 installs within 2 hours; paused for 11h"))
        #expect(!result.reason.contains("Needs install because"))
        let until = g.packageState(name: "foo")?.suppressedUntil
        #expect(until != nil)
        let cause = g.suppressionCause(name: "Foo")
        #expect(cause == "Needs install because installs[0] application /Applications/Foo.app: CFBundleShortVersionString 1.0 is older than the catalog's 1.1 [version_outdated, unchanged over all 3 attempts]")
    }

    @Test func sameVersionTiersEscalateWithAttempts() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        // spread attempts beyond the rapid-fire window
        attempts(g, count: 3, spacing: 3 * 3600)
        var state = g.packageState(name: "Foo")!
        #expect(state.suppressionReason == "installed 3 times across 3 sessions")
        #expect(abs(state.suppressedUntil!.timeIntervalSince(clock(g).now) - 6 * 3600) < 3600 * 3 + 1)
        g.clearLoop(name: "Foo")
        attempts(g, count: 5, spacing: 3 * 3600)
        state = g.packageState(name: "Foo")!
        #expect(state.suppressionReason == "installed 5 times across 5 sessions")
        g.clearLoop(name: "Foo")
        attempts(g, count: 8, spacing: 3 * 3600)
        state = g.packageState(name: "Foo")!
        #expect(state.suppressionReason == "installed 8 times across 8 sessions")
        #expect(state.suppressedUntil!.timeIntervalSince(clock(g).now) > 6 * 86400)
    }

    @Test func expiredWindowRetriesThenEscalates() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        attempts(g, count: 3)
        #expect(g.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1").suppress)
        clock(g).now = clock(g).now.addingTimeInterval(13 * 3600)
        let retry = g.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1")
        #expect(retry.suppress == false)
        #expect(g.packageState(name: "Foo")?.suppressionCycles == 1)
        #expect(g.packageState(name: "Foo")?.attemptCount == 0)
        attempts(g, count: 3)
        let again = g.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1")
        #expect(again.suppress)
        #expect(again.reason.contains("escalated to 1d 0h after 1 prior suppression window(s)"))
    }

    @Test func clearLoopAndClearAll() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        attempts(g, count: 3)
        attempts(g, name: "Bar", count: 3)
        #expect(g.clearLoop(name: "Nope") == false)
        #expect(g.clearLoop(name: "FOO"))
        #expect(g.shouldSuppress(name: "Foo", version: "1.1").suppress == false)
        #expect(g.clearAll() == 1)
        #expect(g.suppressedPackages().isEmpty)
    }

    @Test func statePersistsAcrossInstancesAndCorruptStateStartsClean() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        attempts(g, count: 3, trigger: trigger)
        let data = try #require(FileManager.default.contents(atPath: "\(root)/reports/state.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wrapper = try #require(json["loop_guard"] as? [String: Any])
        let packages = try #require(wrapper["packages"] as? [String: Any])
        let foo = try #require(packages["foo"] as? [String: Any])
        #expect(foo["catalog_fingerprint"] as? String == "fp1")
        #expect((foo["trigger"] as? [String: Any])?["reason_code"] as? String == "version_outdated")

        let g2 = makeGuard(root)
        #expect(g2.packageState(name: "Foo")?.attemptCount == 3)
        #expect(g2.packageState(name: "Foo")?.trigger == trigger)
        #expect(g2.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1").suppress)

        try Data("not json".utf8).write(to: URL(fileURLWithPath: "\(root)/reports/state.json"))
        let g3 = makeGuard(root)
        #expect(g3.packageState(name: "Foo") == nil)
    }

    @Test func bootstrapAndDisabledNeverSuppress() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        attempts(g, count: 3)
        #expect(makeGuard(root, bootstrap: true).shouldSuppress(name: "Foo", version: "1.1").suppress == false)
        let disabled = makeGuard(root, disabled: true)
        #expect(disabled.shouldSuppress(name: "Foo", version: "1.1").suppress == false)
        disabled.recordAttempt(name: "Baz", version: "1", success: true)
        #expect(disabled.packageState(name: "Baz") == nil)
    }

    @Test func selfReportedWarningDoesNotCountAsAnAttempt() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        for _ in 0 ..< 3 {
            g.recordAttempt(name: "Foo", version: "1.1", success: true, selfReportedWarning: true)
        }
        #expect(g.packageState(name: "Foo") == nil)
    }

    @Test func catalogChangeAutoClearsAndResetsHistory() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        attempts(g, count: 3, trigger: trigger)
        #expect(g.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1").suppress)
        let same = g.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1")
        #expect(same.suppress)
        let changed = g.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp2")
        #expect(changed.suppress == false)
        #expect(changed.reason == "Auto-cleared: catalog changed (pkgsinfo fields updated, same version 1.1)")
        let state = g.packageState(name: "Foo")!
        #expect(state.attemptCount == 0)
        #expect(state.processedSessions.isEmpty)
        #expect(state.triggerCounts.isEmpty)
        #expect(state.trigger == nil)
        #expect(state.suppressionCycles == 0)

        attempts(g, count: 3)
        let versionChange = g.shouldSuppress(name: "Foo", version: "1.2", catalogFingerprint: "fp3")
        #expect(versionChange.reason == "Auto-cleared: catalog changed (version 1.1 → 1.2)")
        attempts(g, name: "Bar", count: 3)
        let noFingerprint = g.shouldSuppress(name: "Bar", version: "2.0")
        #expect(noFingerprint.reason == "Auto-cleared: catalog version changed from 1.1 to 2.0")
    }

    @Test func multipleTriggersSummarise() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        let missing = InstallTrigger.from(reasonCode: "file_missing", detectionMethod: "installs_array", detail: "installs[1] file /usr/local/bin/foo: not present")!
        g.setCurrentSession(id: "s1"); g.recordAttempt(name: "Foo", version: "1.1", success: true, trigger: trigger)
        g.setCurrentSession(id: "s2"); g.recordAttempt(name: "Foo", version: "1.1", success: true, trigger: trigger)
        g.setCurrentSession(id: "s3"); g.recordAttempt(name: "Foo", version: "1.1", success: true, trigger: missing)
        let cause = g.suppressionCause(name: "Foo")!
        #expect(cause.hasPrefix("Needs install because installs[1] file /usr/local/bin/foo: not present [most recent of 3 attempts: version_outdated x2, file_missing x1]"))
        // a suppressed evaluation refreshes the cause without counting
        _ = g.shouldSuppress(name: "Foo", version: "1.1", trigger: trigger)
        #expect(g.packageState(name: "Foo")?.triggerCounts.values.reduce(0, +) == 3)
        #expect(g.packageState(name: "Foo")?.attemptCount == 3)
    }

    @Test func noTriggerSaysNotRecordedYet() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        attempts(g, count: 1)
        #expect(g.suppressionCause(name: "Foo") == "Needs install because the cause was not recorded yet — it is captured on the next check")
        #expect(g.suppressionCause(name: "Unknown") == nil)
    }

    @Test func triggerDetailIsFlattenedAndTruncated() {
        let long = String(repeating: "x ", count: 400)
        let t = InstallTrigger.from(reasonCode: "c", detectionMethod: nil, detail: "a\n\n  b\t c " + long)!
        #expect(t.detectionMethod == "none")
        #expect(t.detail.hasPrefix("a b c x x"))
        #expect(t.detail.count <= InstallTrigger.maxDetailLength + 1)
        #expect(t.detail.hasSuffix("…"))
        #expect(InstallTrigger.from(reasonCode: "", detectionMethod: "x", detail: "  ") == nil)
    }

    @Test func markNonConvergedSuppressesAndReplays() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        let reason = g.markNonConverged(name: "Foo", version: "1.1", catalogFingerprint: "fp1", reprobeHours: 24, trigger: trigger)
        #expect(reason == "installcheck still reported action needed immediately after a successful install")
        let replay = g.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1")
        #expect(replay.suppress)
        #expect(replay.reason == "Looping install detected: Foo v1.1 — installcheck still reported action needed immediately after a successful install; paused for 1d 0h")
        let reload = makeGuard(root)
        #expect(reload.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1").suppress)
        let cleared = reload.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp2")
        #expect(cleared.suppress == false)
        #expect(cleared.reason.hasPrefix("Auto-cleared"))
    }

    @Test func pendingRestartDefersUntilRebootOrCatalogChange() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        #expect(g.shouldDeferForRestart(name: "Foo").defer == false)
        g.recordPendingRestart(name: "Foo", version: "1.1", catalogFingerprint: "fp1")
        let deferred = g.shouldDeferForRestart(name: "Foo", catalogFingerprint: "fp1")
        #expect(deferred.defer)
        #expect(deferred.reason == "Pending restart: Foo v1.1 installed successfully and is finalized by a reboot — reinstall deferred until the machine restarts")
        clock(g).boot = clock(g).now.addingTimeInterval(600)
        clock(g).now = clock(g).now.addingTimeInterval(900)
        #expect(g.shouldDeferForRestart(name: "Foo", catalogFingerprint: "fp1").defer == false)
        #expect(g.packageState(name: "Foo")?.pendingRestartSince == nil)

        g.recordPendingRestart(name: "Bar", version: "2.0", catalogFingerprint: "fp1")
        #expect(g.shouldDeferForRestart(name: "Bar", catalogFingerprint: "fp2").defer == false)
        let report = g.suppressedReport()
        #expect(report.isEmpty)
    }

    @Test func fingerprintIsDeterministicSixteenLowercaseHex() {
        let a = LoopGuard.computeFingerprint("one|two")
        #expect(a == LoopGuard.computeFingerprint("one|two"))
        #expect(a != LoopGuard.computeFingerprint("one|three"))
        #expect(a.count == 16)
        #expect(a.allSatisfy { "0123456789abcdef".contains($0) })
        let pkginfo: PlistDict = ["name": "Foo", "version": "1.0", "installs": [["type": "application", "path": "/Applications/Foo.app", "CFBundleShortVersionString": "1.0"]]]
        var changed = pkginfo
        changed["installs"] = [["type": "application", "path": "/Applications/Foo.app", "CFBundleShortVersionString": "1.1"]]
        #expect(LoopGuard.catalogFingerprint(for: pkginfo) == LoopGuard.catalogFingerprint(for: pkginfo))
        #expect(LoopGuard.catalogFingerprint(for: pkginfo) != LoopGuard.catalogFingerprint(for: changed))
        let stamped: PlistDict = ["name": "Foo", "loop_fingerprint": "abc"]
        #expect(LoopGuard.catalogFingerprint(for: stamped) == LoopGuard.computeFingerprint("abc|\(LoopGuard.clientVersion)"))
        // a makecatalogs stamp and a client's own computation agree
        var stampedCopy = pkginfo
        stampedCopy["loop_fingerprint"] = LoopGuard.canonicalFingerprint(for: pkginfo)
        #expect(LoopGuard.catalogFingerprint(for: stampedCopy) == LoopGuard.catalogFingerprint(for: pkginfo))
        #expect(LoopGuard.canonicalFingerprint(for: stampedCopy) == LoopGuard.canonicalFingerprint(for: pkginfo))
        #expect(LoopGuard.canonicalFingerprint(for: pkginfo) != LoopGuard.canonicalFingerprint(for: changed))
    }

    @Test func historyRebuildsFromEventsAndArchives() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fm = FileManager.default
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // three sessions in events.jsonl, one minute apart, laid out the way
        // the session log does: logs/yyyy-MM-dd/HHmm/events.jsonl
        for i in 0 ..< 3 {
            let start = base.addingTimeInterval(TimeInterval(i * 60))
            let sessionId = LoopGuard.sessionId(for: start)
            let day = String(sessionId.prefix(10))
            let time = String(sessionId.suffix(4))
            let dir = "\(root)/logs/\(day)/\(time)"
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let stamp = iso.string(from: start)
            let lines = [
                #"{"event_type":"install","action":"install","status":"started","package_name":"Foo","package_version":"1.1","timestamp":"\#(stamp)","session_id":"\#(sessionId)"}"#,
                #"{"event_type":"install","action":"install","status":"completed","package_name":"Foo","package_version":"1.1","timestamp":"\#(stamp)","session_id":"\#(sessionId)"}"#,
                #"{"event_type":"status_check","package_name":"Foo","timestamp":"\#(stamp)","session_id":"\#(sessionId)"}"#,
            ]
            try lines.joined(separator: "\n").write(toFile: "\(dir)/events.jsonl", atomically: true, encoding: .utf8)
        }
        // one archived report for a fourth session, and one that duplicates an events session
        try fm.createDirectory(atPath: "\(root)/Archives", withIntermediateDirectories: true)
        let fourth = base.addingTimeInterval(4 * 60)
        let archive: PlistDict = ["StartTime": fourth, "InstallResults": [["name": "Foo", "version": "1.1", "status": 0, "time": fourth]]]
        try writePlist(archive, toFile: "\(root)/Archives/ManagedInstallReport-fourth.plist")
        // same session as the first events.jsonl entry: must not count twice
        let duplicate: PlistDict = ["StartTime": base, "InstallResults": [["name": "Foo", "version": "1.1", "status": 0, "time": base]]]
        try writePlist(duplicate, toFile: "\(root)/Archives/ManagedInstallReport-duplicate.plist")

        let g = makeGuard(root)
        clock(g).now = fourth.addingTimeInterval(60)
        let state = g.packageState(name: "Foo")!
        #expect(state.attemptCount == 4)
        #expect(state.sessionCount == 4)
        #expect(g.shouldSuppress(name: "Foo", version: "1.1").suppress)

        // a clear sticks across the next rebuild
        g.clearAll()
        let g2 = makeGuard(root)
        clock(g2).now = fourth.addingTimeInterval(120)
        #expect(g2.packageState(name: "Foo")?.attemptCount ?? 0 == 0)
        #expect(g2.shouldSuppress(name: "Foo", version: "1.1").suppress == false)
        // and fresh attempts after the clear still trip
        attempts(g2, count: 3)
        #expect(g2.shouldSuppress(name: "Foo", version: "1.1", catalogFingerprint: "fp1").suppress)
    }

    @Test func cacheCheckAndDiagnostics() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        #expect(g.checkCacheForPackage(name: "Foo").hasCache == false)
        try FileManager.default.createDirectory(atPath: "\(root)/Cache", withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: "\(root)/Cache/Foo-1.1.pkg"))
        #expect(g.checkCacheForPackage(name: "Foo").hasCache)
        try FileManager.default.createDirectory(atPath: "\(root)/Cache/Bar", withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: "\(root)/Cache/Bar/inner.pkg"))
        #expect(g.checkCacheForPackage(name: "Bar").cachePath?.hasSuffix("Bar/inner.pkg") == true)
        #expect(g.diagnosticInfo(name: "Nope") == "Nope: no loop history")
        attempts(g, count: 3, trigger: trigger)
        let info = g.diagnosticInfo(name: "Foo")
        #expect(info.contains("Attempts: 3 across 3 sessions"))
        #expect(info.contains("Cache: HIT"))
        #expect(info.contains("Needs install because installs[0] application"))
        #expect(info.contains("Reason: 3 installs within 2 hours"))
    }

    @Test func suppressedReportCarriesTriggerAndClearCommand() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let g = makeGuard(root)
        attempts(g, count: 3, trigger: trigger)
        let report = g.suppressedReport()
        #expect(report.count == 1)
        #expect(report[0].packageName == "Foo")
        #expect(report[0].clearCommand == "managedsoftwareupdate --clear-loop Foo")
        #expect(report[0].triggerSummary?.contains("/Applications/Foo.app") == true)
        #expect(report[0].cause?.hasPrefix("Needs install because") == true)
        let plist = report[0].plist
        #expect((plist["trigger"] as? PlistDict)?["reason_code"] as? String == "version_outdated")
    }

    @Test func formatDuration() {
        #expect(LoopGuard.formatDuration(5 * 60) == "5m")
        #expect(LoopGuard.formatDuration(11 * 3600 + 59 * 60) == "11h 59m")
        #expect(LoopGuard.formatDuration(7 * 86400) == "7d 0h")
    }

    @Test func itemsJSONCarriesLoopSuppression() {
        let item = LoopSuppressedReportItem(
            packageName: "Foo", version: "1.1",
            reason: "Looping install detected: Foo v1.1 — 3 installs within 2 hours; paused for 11h 59m",
            cause: "Needs install because installs[0] application /Applications/Foo.app: not present [file_missing]",
            trigger: nil, triggerSummary: nil, suppressedUntil: Date(), pendingRestart: false,
            suppressionCycles: 0, attemptCount: 3, sessionCount: 3, clearCommand: "managedsoftwareupdate --clear-loop Foo"
        )
        let records = SessionLog.buildItems(from: ["ManagedInstalls": [["name": "Foo", "version_to_install": "1.1", "installed": true]]],
                                            session: nil, loopSuppressed: [item])
        #expect(records.count == 1)
        #expect(records[0].currentStatus == "Warning")
        #expect(records[0].actionPerformed == "loop_suppressed")
        #expect(records[0].statusReasonCode == "loop_suppressed")
        #expect(records[0].installLoopDetected == true)
        #expect(records[0].warningMessages?.count == 2)
        #expect(records[0].lastWarning == item.reason + "\n" + item.cause!)
    }
}
