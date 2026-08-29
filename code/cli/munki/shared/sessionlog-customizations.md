# Session logging and reports

Fork addition: structured, per-run session logs and machine-readable reports, matching the layout and schema Cimian writes on Windows so one reader works on both platforms.

---

## What it writes

Each `managedsoftwareupdate` run gets a directory under the existing `Logs/` tree. The tree is day-nested; the flat logs Munki has always written stay where they are.

```
/Library/Managed Installs/Logs/
├── ManagedSoftwareUpdate.log            unchanged
├── Install.log                          unchanged
├── 2026-08-29/
│   ├── 1403/
│   │   ├── session.json                 the run: type, timing, environment, summary, warning_items, error_items
│   │   ├── events.jsonl                 one structured record per install, removal, status check, warning, error
│   │   ├── run.log                      this run's lines from ManagedSoftwareUpdate.log
│   │   └── install.log                  this run's lines from Install.log
│   └── 1503/
└── 2026-08-28/
```

`/Library/Managed Installs/reports/` always describes the latest state and is rewritten at the end of every run:

| File | Content |
|------|---------|
| `run.log` | The current run only |
| `sessions.json` | `session.json` of the newest 100 sessions, newest first |
| `events.json` | Events from the newest 10 sessions within the last 48 hours |
| `items.json` | One record per managed item with its outcome this run |

Session ids are `YYYY-MM-DD-HHMM`; a second run in the same minute gets `_2` … `_9`. Day directories older than 30 days are removed at the start of each run; nothing else under `Logs/` is touched.

`ManagedInstallReport.plist` is untouched. Managed Software Center, the notifier and the existing ReportMate installs module keep reading it.

## Why `Logs/` and not `logs/`

Cimian writes `%ProgramData%\ManagedInstalls\logs`. APFS is case-insensitive by default, so `logs/` and Munki's `Logs/` are the same directory; the day-nested tree lives inside `Logs/` beside the flat files.

## Item attribution

Every warning and error goes through `DisplayAndLog.main`, which has no item in scope. `SessionLog` keeps a stack of the item currently being processed — pushed in `processInstall` / `processRemoval` (check phase) and `installWithInstallInfo` / `processRemovals` (install phase) — and stamps it onto each problem. `session.json` therefore carries `warning_items` and `error_items` as `{name, version, message}`, which is what a reporting client needs to show "SecureShellClient 2026.08.28: postinstall returned 1" instead of a run-level string. Problems raised outside any item (catalog download, manifest fetch) carry no name.

## Files

| File | Role |
|------|------|
| `shared/sessionlog.swift` | The subsystem: `SessionLog`, record types, reports, retention. Self-contained. |
| `shared/display.swift` | `error()` / `warning()` call `SessionLog.shared.recordProblem` |
| `shared/munkilog.swift` | `munkiLog()` mirrors each line into the session copy |
| `managedsoftwareupdate/managedsoftwareupdate.swift` | `start` after `initializeReport()`, `end` before the ending log line, `abandon` on preflight failure |
| `shared/installer/installer.swift` | Item context plus `install` / `uninstall` events (`started`, `completed`, `failed`) |
| `shared/updatecheck/analyze.swift` | Item context plus a `status_check` event per evaluated item |
| `munkiCLItesting/sessionlogTests.swift` | Tests against a temporary root |

The Xcode project compiles `sessionlog.swift` into the same six targets as `reports.swift`. The test target additionally gained `yamlutils.swift` and the Yams product so it builds again.

## Schema

`session.json`

| Field | Meaning |
|-------|---------|
| `session_id`, `start_time`, `end_time`, `duration_seconds` | Identity and timing (ISO 8601, local offset) |
| `run_type` | Munki's runtype (`auto`, `custom`, `manualcheck`, …) |
| `status` | `running` → `completed` / `partial_failure` / `failed` |
| `summary` | `total_actions`, `installs`, `updates`, `removals`, `successes`, `failures`, `warnings`, `errors`, `packages_handled` |
| `environment` | `hostname`, `user`, `os_version`, `architecture`, `process_id`, `log_version`, `munki_version`, `client_identifier`, run flags |
| `warning_items`, `error_items` | `{name?, version?, message}` |

`events.jsonl` records: `event_id`, `session_id`, `timestamp`, `level`, `event_type` (`install`, `status_check`, `warning`, `error`), `package_name`, `package_version`, `action` (`install`, `uninstall`), `status`, `message`, `error`, `status_reason`, `status_reason_code`, `detection_method` (`installs_array`, `receipts`, `script`, `none`), `installed_version`, `target_version`, `context.needs_action`.

`items.json` records: `id`, `item_name`, `display_name`, `item_type`, `current_status` (`Installed`, `Pending`, `Removed`, `Warning`, `Error`), `latest_version`, `installed_version`, `last_seen_in_session`, `last_attempt_time`, `last_attempt_status`, `last_update`, `failure_count`, `warning_count`, `type` (`munki`), `last_error`, `last_warning`, `action_performed`.

## Not included

LoopGuard (install-loop detection and suppression, `state.json`, `loop_suppressed.json`) is a separate feature. The schema leaves room for it: `status_reason_code: loop_suppressed` and `action_performed: loop_suppressed` are reserved.

## Merging upstream

`sessionlog.swift`, `sessionlogTests.swift` and this file are ours. The hooks are single lines or small blocks in the five upstream files listed above; on conflict, re-apply them after accepting upstream.
