//
//  sessionlogTests.swift
//  munkiCLItesting
//

import Foundation
import Testing

struct SessionLogTests {
    private func makeTempRoot() -> String {
        let root = NSTemporaryDirectory() + "sessionlog-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    private func json(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test func sessionDirectoryIsDayNested() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let log = SessionLog(baseDir: root)
        let id = log.start(runType: "auto")
        #expect(id.count == 15)
        let day = String(id.prefix(10))
        let time = String(id.suffix(4))
        #expect(log.sessionDir == "\(root)/logs/\(day)/\(time)")
        for name in ["session.json", "events.jsonl", "install.log", "run.log"] {
            #expect(FileManager.default.fileExists(atPath: "\(log.sessionDir)/\(name)"), "\(name) missing")
        }
        #expect(FileManager.default.fileExists(atPath: "\(root)/reports/run.log"))
        log.end(status: "completed", summary: SessionSummary())
    }

    @Test func problemsAreAttributedToTheCurrentItem() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let log = SessionLog(baseDir: root)
        log.start(runType: "auto")
        log.beginItem(name: "Firefox", version: "140.0", displayName: "Firefox")
        log.recordProblem(isError: false, message: "Postinstall script for Firefox returned 1")
        log.endItem()
        log.recordProblem(isError: true, message: "Could not download catalog Production")
        log.end(status: "partial_failure", summary: SessionSummary())

        let session = try #require(json(at: "\(log.sessionDir)/session.json"))
        let warnings = try #require(session["warning_items"] as? [[String: Any]])
        #expect(warnings.count == 1)
        #expect(warnings[0]["name"] as? String == "Firefox")
        #expect(warnings[0]["version"] as? String == "140.0")
        let errors = try #require(session["error_items"] as? [[String: Any]])
        #expect(errors.count == 1)
        #expect(errors[0]["name"] == nil)
        let summary = try #require(session["summary"] as? [String: Any])
        #expect(summary["warnings"] as? Int == 1)
        #expect(summary["errors"] as? Int == 1)
        #expect(session["status"] as? String == "partial_failure")
        #expect(session["end_time"] != nil)

        let events = try String(contentsOfFile: "\(log.sessionDir)/events.jsonl", encoding: .utf8)
            .split(separator: "\n")
        #expect(events.count == 2)
        #expect(events[0].contains("\"event_type\":\"warning\""))
        #expect(events[0].contains("\"package_name\":\"Firefox\""))
    }

    @Test func installEventsAndReportsAreWritten() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let log = SessionLog(baseDir: root)
        log.start(runType: "manual")
        log.logInstall(name: "Chrome", version: "150.0", action: "install", status: "started", message: "Installing Chrome")
        log.logInstall(name: "Chrome", version: "150.0", action: "install", status: "completed", message: "Install of Chrome-150.0: SUCCESSFUL")
        log.logStatusCheck(name: "Slack", version: "4.40", status: "installed", statusReason: "installs array matched",
                           statusReasonCode: "file_match", detectionMethod: "installs_array", installedVersion: "4.40")
        log.end(status: "completed", summary: SessionSummary())

        let events = try String(contentsOfFile: "\(log.sessionDir)/events.jsonl", encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(events.count == 3)
        let first = try #require(try JSONSerialization.jsonObject(with: Data(events[0].utf8)) as? [String: Any])
        #expect(first["action"] as? String == "install")
        #expect(first["level"] as? String == "DEBUG")
        #expect(first["target_version"] as? String == "150.0")
        let third = try #require(try JSONSerialization.jsonObject(with: Data(events[2].utf8)) as? [String: Any])
        #expect(third["event_type"] as? String == "status_check")
        #expect((third["context"] as? [String: Any])?["needs_action"] as? Bool == false)

        let sessionsData = try #require(FileManager.default.contents(atPath: "\(root)/reports/sessions.json"))
        let sessions = try #require(try JSONSerialization.jsonObject(with: sessionsData) as? [[String: Any]])
        #expect(sessions.count == 1)
        #expect(sessions[0]["session_id"] as? String == log.sessionId)
        let eventsData = try #require(FileManager.default.contents(atPath: "\(root)/reports/events.json"))
        let reportEvents = try #require(try JSONSerialization.jsonObject(with: eventsData) as? [[String: Any]])
        #expect(reportEvents.count == 3)
    }

    @Test func secondSessionInSameMinuteGetsSuffix() {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let first = SessionLog(baseDir: root)
        first.start(runType: "auto")
        first.end(status: "completed", summary: SessionSummary())
        let second = SessionLog(baseDir: root)
        let id = second.start(runType: "auto")
        #expect(id.hasSuffix("_2") || id != first.sessionId)
        #expect(SessionLog.allSessionDirs(logsDir: "\(root)/logs").count == 2)
        #expect(SessionLog.latestSessionDir(logsDir: "\(root)/logs") == second.sessionDir)
        second.end(status: "completed", summary: SessionSummary())
    }

    @Test func itemsReportReflectsResults() {
        let report: [String: Any] = [
            "ManagedInstalls": [
                ["name": "Chrome", "display_name": "Google Chrome", "installed": true, "installed_version": "150.0", "version_to_install": "150.0"],
                ["name": "Slack", "installed": false, "version_to_install": "4.40"],
            ],
            "InstallResults": [
                ["name": "Slack", "display_name": "Slack", "version": "4.40", "status": 1, "time": Date()],
            ],
        ]
        var session = SessionRecord(sessionId: "2026-08-29-1500", startTime: Date(), endTime: nil, runType: "auto",
                                    status: "running", durationSeconds: nil, summary: SessionSummary(), environment: [:],
                                    warningItems: [SessionProblem(name: "Chrome", version: "150.0", message: "Postinstall returned 1")],
                                    errorItems: [])
        session.status = "partial_failure"
        let items = SessionLog.buildItems(from: report, session: session)
        #expect(items.count == 2)
        let chrome = items[0]
        #expect(chrome.itemName == "Chrome")
        #expect(chrome.currentStatus == "Warning")
        #expect(chrome.lastWarning == "Postinstall returned 1")
        let slack = items[1]
        #expect(slack.currentStatus == "Error")
        #expect(slack.failureCount == 1)
        #expect(slack.actionPerformed == "install")
        #expect(slack.lastSeenInSession == "2026-08-29-1500")
    }

    @Test func pruneRemovesOnlyOldDayDirectories() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let logs = "\(root)/logs"
        let fm = FileManager.default
        for name in ["2026-01-01", "2099-01-01", "ManagedSoftwareUpdate.log"] {
            try fm.createDirectory(atPath: "\(logs)/\(name)", withIntermediateDirectories: true)
        }
        SessionLog.pruneOldSessions(in: logs, now: Date())
        #expect(!fm.fileExists(atPath: "\(logs)/2026-01-01"))
        #expect(fm.fileExists(atPath: "\(logs)/2099-01-01"))
        #expect(fm.fileExists(atPath: "\(logs)/ManagedSoftwareUpdate.log"))
    }

    @Test func existingLogsDirectoryIsRenamedToLowercase() throws {
        let root = makeTempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fm = FileManager.default
        try fm.createDirectory(atPath: "\(root)/Logs", withIntermediateDirectories: true)
        fm.createFile(atPath: "\(root)/Logs/ManagedSoftwareUpdate.log", contents: Data("x".utf8))
        let log = SessionLog(baseDir: root)
        log.start(runType: "auto")
        log.end(status: "completed", summary: SessionSummary())
        let names = try fm.contentsOfDirectory(atPath: root)
        #expect(names.contains("logs"))
        #expect(!names.contains("Logs"))
        #expect(fm.fileExists(atPath: "\(root)/logs/ManagedSoftwareUpdate.log"))
    }

    @Test func directoryNameValidation() {
        #expect(SessionLog.isDayDirectory("2026-08-29"))
        #expect(!SessionLog.isDayDirectory("2026-8-29"))
        #expect(!SessionLog.isDayDirectory("Install.log"))
        #expect(SessionLog.isTimeDirectory("1403"))
        #expect(SessionLog.isTimeDirectory("1403_2"))
        #expect(!SessionLog.isTimeDirectory("2460"))
        #expect(!SessionLog.isTimeDirectory("14:03"))
    }
}
