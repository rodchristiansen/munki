//
//  sessionlog.swift
//  munki
//
//  Structured, per-run session logging and machine-readable reports.
//
//  Every managedsoftwareupdate run gets its own directory,
//      <ManagedInstallDir>/logs/YYYY-MM-DD/HHMM/
//  holding session.json (the run: type, timing, environment, summary, and
//  every warning and error attributed to the item that raised it),
//  events.jsonl (one structured record per install, removal, status check,
//  warning or error), and run.log / install.log (plain-text copies of what
//  went to ManagedSoftwareUpdate.log and Install.log during this run).
//
//  <ManagedInstallDir>/reports/ always describes the latest state:
//  run.log for the current run, sessions.json (last 100 sessions),
//  events.json (events from the last 10 sessions, 48h), and items.json
//  (one record per managed item with its outcome this run).
//
//  ManagedInstallReport.plist and the flat logs are untouched; this sits
//  beside them. The layout and schema match Cimian's SessionLogger so the
//  same readers work on both platforms.
//
//  Fork customization: see shared/sessionlog-customizations.md.
//

import Foundation
import SystemConfiguration

// MARK: - Records

/// A warning or error raised during the run, attributed to a managed item
/// when one was being processed at the time.
struct SessionProblem: Codable {
    var name: String?
    var version: String?
    var message: String
}

/// Counts for the run, written into session.json at the end.
struct SessionSummary: Codable {
    var totalActions = 0
    var installs = 0
    var updates = 0
    var removals = 0
    var successes = 0
    var failures = 0
    var warnings = 0
    var errors = 0
    var packagesHandled = [String]()
}

/// The session record written to session.json.
struct SessionRecord: Codable {
    var sessionId: String
    var startTime: Date
    var endTime: Date?
    var runType: String
    var status: String
    var durationSeconds: Int?
    var summary: SessionSummary
    var environment: [String: JSONValue]
    var warningItems: [SessionProblem]
    var errorItems: [SessionProblem]
}

/// One line of events.jsonl.
struct SessionEvent: Codable {
    var eventId: String = ""
    var sessionId: String = ""
    var timestamp: Date = Date()
    var level: String = "INFO"
    var eventType: String
    var packageName: String?
    var packageVersion: String?
    var action: String = ""
    var status: String
    var message: String
    var error: String?
    var context: [String: JSONValue]?
    var statusReason: String?
    var statusReasonCode: String?
    var detectionMethod: String?
    var installedVersion: String?
    var targetVersion: String?
}

/// One entry of reports/items.json.
struct SessionItemRecord: Codable {
    var id: String
    var itemName: String
    var displayName: String?
    var itemType: String
    var currentStatus: String
    var latestVersion: String
    var installedVersion: String?
    var lastSeenInSession: String
    var lastAttemptTime: String
    var lastAttemptStatus: String
    var lastUpdate: String
    var failureCount: Int
    var warningCount: Int
    var type: String = "munki"
    var lastError: String
    var lastWarning: String?
    var actionPerformed: String?
    /// The warning split into its parts, so a consumer can render them as
    /// separate messages; `lastWarning` holds them joined.
    var warningMessages: [String]? = nil
    var installLoopDetected: Bool? = nil
    var statusReason: String? = nil
    var statusReasonCode: String? = nil
    var detectionMethod: String? = nil
}

/// Minimal JSON value so environment metadata can hold mixed scalars.
enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case double(Double)
    case null

    init(_ value: Any) {
        switch value {
        case let v as Bool: self = .bool(v)
        case let v as Int: self = .int(v)
        case let v as Double: self = .double(v)
        case let v as String: self = .string(v)
        default: self = .string(String(describing: value))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        self = .string(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(v): try container.encode(v)
        case let .int(v): try container.encode(v)
        case let .bool(v): try container.encode(v)
        case let .double(v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

/// The managed item currently being processed, so problems raised by code
/// that has no item in scope (installer output, package removal) are still
/// attributed correctly.
struct SessionItemContext {
    var name: String
    var version: String
    var displayName: String
}

// MARK: - SessionLog

final class SessionLog {
    static let shared = SessionLog()

    static let logVersion = "2.0"
    static let retentionDays = 30
    static let sessionsInReport = 100
    static let sessionsInEventsReport = 10
    static let eventsReportWindow: TimeInterval = 48 * 3600

    /// Root of the managed installs tree. Injectable for tests.
    var baseDir: String

    private(set) var sessionId = ""
    private(set) var sessionDir = ""
    private(set) var isActive = false

    private var record: SessionRecord?
    private var installLog: FileHandle?
    private var runLog: FileHandle?
    private var reportRunLog: FileHandle?
    private var eventsFile: FileHandle?
    private let lock = NSLock()
    private var contextStack = [SessionItemContext]()

    init(baseDir: String? = nil) {
        self.baseDir = baseDir ?? managedInstallsDir()
    }

    var logsDir: String { (baseDir as NSString).appendingPathComponent("logs") }
    var reportsDir: String { (baseDir as NSString).appendingPathComponent("reports") }

    /// The managed item whose processing is in progress, if any.
    var currentItem: SessionItemContext? {
        lock.lock(); defer { lock.unlock() }
        return contextStack.last
    }

    /// Marks the start of processing for an item. Nested calls (dependency
    /// resolution) stack; pop with `endItem()`.
    func beginItem(name: String, version: String = "", displayName: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        contextStack.append(SessionItemContext(name: name, version: version, displayName: displayName ?? name))
    }

    /// Updates the innermost item context once more is known (version, display name).
    func updateItem(version: String? = nil, displayName: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard var top = contextStack.popLast() else { return }
        if let version { top.version = version }
        if let displayName { top.displayName = displayName }
        contextStack.append(top)
    }

    func endItem() {
        lock.lock(); defer { lock.unlock() }
        _ = contextStack.popLast()
    }

    // MARK: Lifecycle

    /// Opens the session: creates the day-nested directory, the log files,
    /// and the initial session.json. Safe to call once per process.
    @discardableResult
    func start(runType: String, metadata: [String: Any] = [:]) -> String {
        lock.lock(); defer { lock.unlock() }
        if isActive { return sessionId }
        Self.adoptLowercaseLogsDirectory(in: baseDir)
        let now = Date()
        let dayName = Self.dayFormatter.string(from: now)
        let timeName = Self.timeFormatter.string(from: now)
        let dayDir = (logsDir as NSString).appendingPathComponent(dayName)
        var dirName = timeName
        var id = "\(dayName)-\(timeName)"
        let fm = FileManager.default
        if fm.fileExists(atPath: (dayDir as NSString).appendingPathComponent(dirName)) {
            for suffix in 2 ... 9 {
                let candidate = "\(timeName)_\(suffix)"
                if !fm.fileExists(atPath: (dayDir as NSString).appendingPathComponent(candidate)) {
                    dirName = candidate
                    id = "\(dayName)-\(candidate)"
                    break
                }
            }
        }
        sessionId = id
        sessionDir = (dayDir as NSString).appendingPathComponent(dirName)
        try? fm.createDirectory(atPath: sessionDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: reportsDir, withIntermediateDirectories: true)

        installLog = Self.openForAppend((sessionDir as NSString).appendingPathComponent("install.log"))
        runLog = Self.openForAppend((sessionDir as NSString).appendingPathComponent("run.log"))
        eventsFile = Self.openForAppend((sessionDir as NSString).appendingPathComponent("events.jsonl"))
        let reportRunLogPath = (reportsDir as NSString).appendingPathComponent("run.log")
        try? fm.removeItem(atPath: reportRunLogPath)
        reportRunLog = Self.openForAppend(reportRunLogPath)

        var environment = Self.environmentInfo()
        for (key, value) in metadata {
            environment[key] = JSONValue(value)
        }
        record = SessionRecord(
            sessionId: id,
            startTime: now,
            endTime: nil,
            runType: runType,
            status: "running",
            durationSeconds: nil,
            summary: SessionSummary(),
            environment: environment,
            warningItems: [],
            errorItems: []
        )
        isActive = true
        writeSessionRecord()
        writeLine("INFO", "Session started: \(id)")
        writeLine("INFO", "Run type: \(runType)")

        let logs = logsDir
        DispatchQueue.global(qos: .background).async {
            Self.pruneOldSessions(in: logs)
        }
        return id
    }

    /// Closes the session: finalises session.json and regenerates reports/.
    func end(status: String, summary: SessionSummary, report: [String: Any] = [:]) {
        lock.lock(); defer { lock.unlock() }
        guard isActive, var rec = record else { return }
        let now = Date()
        rec.endTime = now
        rec.status = status
        rec.durationSeconds = Int(now.timeIntervalSince(rec.startTime))
        var finalSummary = summary
        finalSummary.warnings = rec.warningItems.count
        finalSummary.errors = rec.errorItems.count
        rec.summary = finalSummary
        record = rec
        writeSessionRecord()
        writeLine("INFO", "Session ended: \(status) (\(rec.durationSeconds ?? 0)s)")
        generateReports(report: report)
        closeFiles()
        isActive = false
    }

    /// Closes the session as failed if it is still open; for exit paths that
    /// never reach the normal finish.
    func abandon(reason: String) {
        guard isActive else { return }
        var summary = SessionSummary()
        summary.failures = 1
        writeLine("ERROR", reason)
        end(status: "failed", summary: summary)
    }

    // MARK: Text logging

    /// Writes a formatted line to run.log and reports/run.log.
    func log(_ level: String, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        writeLine(level, message)
    }

    /// Mirrors a line already written to one of Munki's flat logs into the
    /// session copy: ManagedSoftwareUpdate.log lines go to run.log,
    /// Install.log lines to install.log. Called from munkiLog().
    func mirror(_ message: String, logFile: String) {
        lock.lock(); defer { lock.unlock() }
        guard isActive else { return }
        let line = "[\(Self.lineFormatter.string(from: Date()))] \(message)\n"
        switch logFile {
        case "", MAIN_LOG_NAME:
            Self.append(line, to: runLog)
            Self.append(line, to: reportRunLog)
        case "Install.log":
            Self.append(line, to: installLog)
        default:
            break
        }
    }

    // MARK: Structured events

    func logEvent(_ event: SessionEvent) {
        lock.lock(); defer { lock.unlock() }
        appendEvent(event)
    }

    /// Records an install or removal step for an item.
    /// status: started | completed | failed | blocked | skipped
    func logInstall(name: String, version: String, action: String, status: String,
                    message: String, error: String? = nil,
                    statusReason: String? = nil, statusReasonCode: String? = nil,
                    detectionMethod: String? = nil, installedVersion: String? = nil)
    {
        let level = switch status {
        case "failed": "ERROR"
        case "completed": "INFO"
        default: "DEBUG"
        }
        var event = SessionEvent(eventType: "install", status: status, message: message)
        event.level = level
        event.packageName = name
        event.packageVersion = version
        event.action = action
        event.error = error
        event.statusReason = statusReason
        event.statusReasonCode = statusReasonCode
        event.detectionMethod = detectionMethod
        event.installedVersion = installedVersion
        event.targetVersion = version
        logEvent(event)
    }

    /// Records the outcome of deciding whether an item needs action.
    /// status: installed | pending | error | skipped | deferred
    func logStatusCheck(name: String, version: String, status: String, statusReason: String,
                        statusReasonCode: String, detectionMethod: String,
                        installedVersion: String? = nil, needsAction: Bool = false)
    {
        var event = SessionEvent(eventType: "status_check", status: status, message: statusReason)
        event.level = "DEBUG"
        event.packageName = name
        event.packageVersion = version
        event.statusReason = statusReason
        event.statusReasonCode = statusReasonCode
        event.detectionMethod = detectionMethod
        event.installedVersion = installedVersion
        event.targetVersion = version
        event.context = ["needs_action": .bool(needsAction)]
        logEvent(event)
    }

    /// Records a warning or error, attributed to the current item when one is
    /// being processed. Called from DisplayAndLog so every call site is covered.
    func recordProblem(isError: Bool, message: String) {
        lock.lock(); defer { lock.unlock() }
        guard isActive, var rec = record else { return }
        let item = contextStack.last
        let problem = SessionProblem(name: item?.name, version: item.flatMap { $0.version.isEmpty ? nil : $0.version }, message: message)
        if isError {
            rec.errorItems.append(problem)
        } else {
            rec.warningItems.append(problem)
        }
        record = rec
        var event = SessionEvent(eventType: isError ? "error" : "warning",
                                 status: isError ? "error" : "warning", message: message)
        event.level = isError ? "ERROR" : "WARN"
        event.packageName = item?.name
        event.packageVersion = problem.version
        appendEvent(event)
    }

    // MARK: Session lookup

    /// The most recent session directory under logs/, or nil.
    static func latestSessionDir(logsDir: String) -> String? {
        allSessionDirs(logsDir: logsDir).first
    }

    /// Every session directory, newest first.
    static func allSessionDirs(logsDir: String) -> [String] {
        let fm = FileManager.default
        guard let days = try? fm.contentsOfDirectory(atPath: logsDir) else { return [] }
        var result = [String]()
        for day in days.filter(isDayDirectory).sorted(by: >) {
            let dayPath = (logsDir as NSString).appendingPathComponent(day)
            guard let times = try? fm.contentsOfDirectory(atPath: dayPath) else { continue }
            for time in times.filter(isTimeDirectory).sorted(by: >) {
                result.append((dayPath as NSString).appendingPathComponent(time))
            }
        }
        return result
    }

    // MARK: - Private

    private func writeLine(_ level: String, _ message: String) {
        guard isActive else { return }
        let paddedLevel = level.padding(toLength: 5, withPad: " ", startingAt: 0)
        let line = "[\(Self.lineFormatter.string(from: Date()))] \(paddedLevel) \(message)\n"
        Self.append(line, to: installLog)
        Self.append(line, to: runLog)
        Self.append(line, to: reportRunLog)
    }

    private func appendEvent(_ event: SessionEvent) {
        guard isActive else { return }
        var event = event
        if event.sessionId.isEmpty { event.sessionId = sessionId }
        if event.eventId.isEmpty {
            event.eventId = "\(sessionId)-\(Int(event.timestamp.timeIntervalSince1970 * 1_000_000))"
        }
        guard let data = try? Self.compactEncoder.encode(event),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        Self.append(line, to: eventsFile)
    }

    private func writeSessionRecord() {
        guard let record, let data = try? Self.prettyEncoder.encode(record) else { return }
        let path = (sessionDir as NSString).appendingPathComponent("session.json")
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func closeFiles() {
        for handle in [installLog, runLog, reportRunLog, eventsFile] {
            handle?.closeFile()
        }
        installLog = nil
        runLog = nil
        reportRunLog = nil
        eventsFile = nil
    }

    private func generateReports(report: [String: Any]) {
        let dirs = Self.allSessionDirs(logsDir: logsDir)
        let fm = FileManager.default

        var sessions = [SessionRecord]()
        for dir in dirs.prefix(Self.sessionsInReport) {
            let path = (dir as NSString).appendingPathComponent("session.json")
            if let data = fm.contents(atPath: path),
               let rec = try? Self.decoder.decode(SessionRecord.self, from: data)
            {
                sessions.append(rec)
            }
        }
        writeReport(sessions, name: "sessions.json")

        let cutoff = Date().addingTimeInterval(-Self.eventsReportWindow)
        var events = [SessionEvent]()
        for dir in dirs.prefix(Self.sessionsInEventsReport) {
            let path = (dir as NSString).appendingPathComponent("events.jsonl")
            guard let data = fm.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                if let event = try? Self.decoder.decode(SessionEvent.self, from: Data(line.utf8)),
                   event.timestamp >= cutoff
                {
                    events.append(event)
                }
            }
        }
        writeReport(events, name: "events.json")

        let items = Self.buildItems(from: report, session: record, loopSuppressed: LoopGuard.shared.suppressedReport())
        if !items.isEmpty {
            writeReport(items, name: "items.json")
        }
    }

    private func writeReport<T: Encodable>(_ value: T, name: String) {
        guard let data = try? Self.prettyEncoder.encode(value) else { return }
        let path = (reportsDir as NSString).appendingPathComponent(name)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Builds items.json from the run report: one record per managed item,
    /// carrying what happened to it this run.
    static func buildItems(from report: [String: Any], session: SessionRecord?,
                           loopSuppressed: [LoopSuppressedReportItem] = []) -> [SessionItemRecord]
    {
        let sessionId = session?.sessionId ?? ""
        let now = isoTimestamp(Date())
        var records = [String: SessionItemRecord]()
        var order = [String]()

        func record(for name: String, version: String, displayName: String?, itemType: String) -> SessionItemRecord {
            if let existing = records[name] { return existing }
            let rec = SessionItemRecord(
                id: name.lowercased().replacingOccurrences(of: " ", with: ""),
                itemName: name,
                displayName: displayName,
                itemType: itemType,
                currentStatus: "Installed",
                latestVersion: version,
                installedVersion: nil,
                lastSeenInSession: "",
                lastAttemptTime: now,
                lastAttemptStatus: "Installed",
                lastUpdate: now,
                failureCount: 0,
                warningCount: 0,
                lastError: "",
                lastWarning: nil,
                actionPerformed: nil
            )
            order.append(name)
            return rec
        }

        for entry in report["ManagedInstalls"] as? [[String: Any]] ?? [] {
            let name = entry["name"] as? String ?? ""
            guard !name.isEmpty else { continue }
            var rec = record(for: name, version: entry["version_to_install"] as? String ?? entry["installed_version"] as? String ?? "",
                             displayName: entry["display_name"] as? String, itemType: "managed_installs")
            let installed = entry["installed"] as? Bool ?? true
            if !installed {
                rec.currentStatus = "Pending"
                rec.lastAttemptStatus = "Pending"
            }
            if let installedVersion = entry["installed_version"] as? String, !installedVersion.isEmpty {
                rec.installedVersion = installedVersion
            }
            records[name] = rec
        }
        for entry in report["ItemsToRemove"] as? [[String: Any]] ?? [] {
            let name = entry["name"] as? String ?? ""
            guard !name.isEmpty else { continue }
            var rec = record(for: name, version: entry["installed_version"] as? String ?? "",
                             displayName: entry["display_name"] as? String, itemType: "managed_uninstalls")
            rec.currentStatus = "Pending"
            rec.lastAttemptStatus = "Pending"
            records[name] = rec
        }
        for entry in report["InstallResults"] as? [[String: Any]] ?? [] {
            let name = entry["name"] as? String ?? ""
            guard !name.isEmpty else { continue }
            var rec = record(for: name, version: entry["version"] as? String ?? "",
                             displayName: entry["display_name"] as? String, itemType: "managed_installs")
            let status = entry["status"] as? Int ?? -1
            rec.actionPerformed = "install"
            rec.lastSeenInSession = sessionId
            if let time = entry["time"] as? Date { rec.lastAttemptTime = isoTimestamp(time) }
            if status == 0 {
                rec.currentStatus = "Installed"
                rec.installedVersion = entry["version"] as? String
            } else {
                rec.currentStatus = "Error"
                rec.failureCount += 1
                rec.lastError = "Install failed with return code \(status)"
            }
            rec.lastAttemptStatus = rec.currentStatus
            records[name] = rec
        }
        for entry in report["RemovalResults"] as? [[String: Any]] ?? [] {
            let name = entry["name"] as? String ?? ""
            guard !name.isEmpty else { continue }
            var rec = record(for: name, version: "", displayName: entry["display_name"] as? String, itemType: "managed_uninstalls")
            let status = entry["status"] as? Int ?? -1
            rec.actionPerformed = "remove"
            rec.lastSeenInSession = sessionId
            if let time = entry["time"] as? Date { rec.lastAttemptTime = isoTimestamp(time) }
            if status == 0 {
                rec.currentStatus = "Removed"
            } else {
                rec.currentStatus = "Error"
                rec.failureCount += 1
                rec.lastError = "Removal failed with return code \(status)"
            }
            rec.lastAttemptStatus = rec.currentStatus
            records[name] = rec
        }
        for problem in session?.errorItems ?? [] {
            guard let name = problem.name, var rec = records[name] else { continue }
            if rec.lastError.isEmpty { rec.lastError = problem.message }
            if rec.actionPerformed == nil {
                rec.currentStatus = "Error"
                rec.lastAttemptStatus = "Error"
                rec.failureCount += 1
                rec.lastSeenInSession = sessionId
            }
            records[name] = rec
        }
        for problem in session?.warningItems ?? [] {
            guard let name = problem.name, var rec = records[name] else { continue }
            rec.warningCount += 1
            if rec.lastWarning == nil { rec.lastWarning = problem.message }
            if rec.currentStatus == "Installed" || rec.currentStatus == "Pending" {
                rec.currentStatus = "Warning"
                rec.lastAttemptStatus = "Warning"
                rec.lastSeenInSession = sessionId
            }
            records[name] = rec
        }
        // Packages the install-loop guard is holding stay in items.json for as
        // long as the hold lasts, whether or not this run touched them.
        for entry in loopSuppressed {
            var rec = records[entry.packageName]
                ?? record(for: entry.packageName, version: entry.version, displayName: nil, itemType: "managed_installs")
            rec.detectionMethod = "none"
            if entry.pendingRestart {
                rec.currentStatus = "Pending"
                rec.lastAttemptStatus = "Pending"
                rec.actionPerformed = "restart_deferred"
                rec.statusReasonCode = "pending_reboot"
                rec.statusReason = entry.reason
                rec.installLoopDetected = false
            } else {
                let parts = [entry.reason] + (entry.cause.map { [$0] } ?? [])
                rec.currentStatus = "Warning"
                rec.lastAttemptStatus = "Warning"
                rec.actionPerformed = "loop_suppressed"
                rec.statusReasonCode = "loop_suppressed"
                rec.warningMessages = parts
                rec.lastWarning = parts.joined(separator: "\n")
                rec.statusReason = rec.lastWarning
                rec.installLoopDetected = true
                if rec.warningCount == 0 { rec.warningCount = 1 }
            }
            if rec.lastSeenInSession.isEmpty { rec.lastSeenInSession = sessionId }
            records[entry.packageName] = rec
        }
        return order.compactMap { records[$0] }
    }

    /// Removes session day directories older than the retention window.
    /// Only directories named YYYY-MM-DD are considered; flat logs are untouched.
    static func pruneOldSessions(in logsDir: String, now: Date = Date()) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: logsDir) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        for entry in entries where isDayDirectory(entry) {
            guard let day = dayFormatter.date(from: entry), day < cutoff else { continue }
            try? fm.removeItem(atPath: (logsDir as NSString).appendingPathComponent(entry))
        }
    }

    /// Munki historically created `Logs/`. Rename it to `logs/` so the on-disk
    /// name is lowercase. On a case-insensitive volume this is a case-only
    /// rename of the same directory; on a case-sensitive one an existing `Logs/`
    /// is renamed only when no `logs/` exists yet, so nothing is ever merged.
    static func adoptLowercaseLogsDirectory(in baseDir: String) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: baseDir), entries.contains("Logs") else { return }
        let old = (baseDir as NSString).appendingPathComponent("Logs")
        let new = (baseDir as NSString).appendingPathComponent("logs")
        if entries.contains("logs") { return }
        _ = rename(old, new)
    }

    static func isDayDirectory(_ name: String) -> Bool {
        name.count == 10 && dayFormatter.date(from: name) != nil
    }

    static func isTimeDirectory(_ name: String) -> Bool {
        let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
        guard let time = parts.first, time.count == 4, let value = Int(time), value >= 0, value <= 2359 else { return false }
        if parts.count == 2 { return parts[1].count == 1 && Int(parts[1]) != nil }
        return true
    }

    static func environmentInfo() -> [String: JSONValue] {
        var machine = utsname()
        uname(&machine)
        let architecture = withUnsafePointer(to: &machine.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var info: [String: JSONValue] = [
            "hostname": .string(ProcessInfo.processInfo.hostName),
            "user": .string(consoleUserName()),
            "os_version": .string("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
            "architecture": .string(architecture),
            "process_id": .int(Int(ProcessInfo.processInfo.processIdentifier)),
            "log_version": .string(logVersion),
        ]
        if let clientIdentifier = stringPref("ClientIdentifier"), !clientIdentifier.isEmpty {
            info["client_identifier"] = .string(clientIdentifier)
        }
        return info
    }

    /// The console user, without depending on helpers that not every tool links.
    static func consoleUserName() -> String {
        guard let name = SCDynamicStoreCopyConsoleUser(nil, nil, nil) as String? else { return "" }
        return name
    }

    static func isoTimestamp(_ date: Date) -> String {
        recordDateFormatter.string(from: date)
    }

    private static func openForAppend(_ path: String) -> FileHandle? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
        _ = handle.seekToEndOfFile()
        return handle
    }

    private static func append(_ line: String, to handle: FileHandle?) {
        guard let handle, let data = line.data(using: .utf8) else { return }
        handle.write(data)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HHmm"
        return f
    }()

    static let lineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static let recordDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone.current
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(recordDateFormatter.string(from: date))
        }
        return e
    }()

    static let compactEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = prettyEncoder.dateEncodingStrategy
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = recordDateFormatter.date(from: s) { return date }
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognised date \(s)")
        }
        return d
    }()
}

extension SessionLog {
    /// Derives the run summary from the run report (ItemsToInstall, ItemsToRemove,
    /// InstallResults, RemovalResults, ManagedInstalls).
    static func summary(from report: [String: Any]) -> SessionSummary {
        var summary = SessionSummary()
        let toInstall = report["ItemsToInstall"] as? [[String: Any]] ?? []
        let toRemove = report["ItemsToRemove"] as? [[String: Any]] ?? []
        summary.installs = toInstall.filter { ($0["installed_version"] as? String ?? "").isEmpty }.count
        summary.updates = toInstall.count - summary.installs
        summary.removals = toRemove.count
        summary.totalActions = toInstall.count + toRemove.count
        let results = (report["InstallResults"] as? [[String: Any]] ?? []) + (report["RemovalResults"] as? [[String: Any]] ?? [])
        summary.successes = results.filter { ($0["status"] as? Int ?? -1) == 0 }.count
        summary.failures = results.count - summary.successes
        var names = [String]()
        for entry in (report["ManagedInstalls"] as? [[String: Any]] ?? []) + toRemove {
            if let name = entry["name"] as? String, !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        summary.packagesHandled = names
        return summary
    }
}
