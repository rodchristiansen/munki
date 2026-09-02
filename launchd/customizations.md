# Launchd Configuration Customizations

**Purpose:** Documents customizations to launchd property lists for Munki services.

**Location:** `launchd/`  
**Upstream:** `https://github.com/munki/munki/tree/main/launchd`

---

## Overview

The launchd plists now match upstream (the "Software Center" app rename was
reverted; the app is "Managed Software Center" as upstream ships it). Historical
customizations that upstream has since adopted:
- AssociatedBundleIdentifiers for macOS notification handling
- Tool paths (`/usr/local/munki/libexec/` structure)

---

## Customized Files

### LaunchAgents (User Context)

| File | Purpose | Key Customizations |
|------|---------|-------------------|
| `com.googlecode.munki.ManagedSoftwareCenter.plist` | Triggers Managed Software Center launch | Matches upstream |
| `com.googlecode.munki.MunkiStatus.plist` | Status display during installs | Matches upstream |
| `com.googlecode.munki.munki-notifier.plist` | User notifications | AssociatedBundleIdentifiers |
| `com.googlecode.munki.managedsoftwareupdate-loginwindow.plist` | Login window installs | Supervisor removal, direct msu invocation |

### LaunchDaemons (System Context)

| File | Purpose | Key Customizations |
|------|---------|-------------------|
| `com.googlecode.munki.authrestartd.plist` | Authenticated restart handling | Path updates |
| `com.googlecode.munki.logouthelper.plist` | Logout-time operations | Path updates |
| `com.googlecode.munki.managedsoftwareupdate-check.plist` | Scheduled check runs | Supervisor removal |
| `com.googlecode.munki.managedsoftwareupdate-install.plist` | Scheduled install runs | Path updates |
| `com.googlecode.munki.managedsoftwareupdate-manualcheck.plist` | Manual check trigger | Path updates |

---

## Key Differences from Upstream

### 1. Application Naming

None. The "Software Center" rename has been reverted; the app is
`/Applications/Managed Software Center.app`, matching upstream.

### 2. Tool Paths

```diff
- /usr/local/munki/launchapp
+ /usr/local/munki/libexec/launchapp
```

Internal tools moved to `libexec/` subdirectory per Munki 7 structure.

### 3. PathState Triggers

None. The PathState trigger is `/var/run/com.googlecode.munki.ManagedSoftwareCenter`,
matching upstream.

### 4. AssociatedBundleIdentifiers

Added for macOS notification permissions:

```xml
<key>AssociatedBundleIdentifiers</key>
<array>
    <string>com.googlecode.munki.ManagedSoftwareCenter</string>
</array>
```

### 5. Supervisor Removal

Munki 7 removed the supervisor wrapper:

```diff
- <string>/usr/local/munki/supervisor</string>
- <string>--timeout</string>
- <string>43200</string>
- <string>--</string>
  <string>/usr/local/munki/managedsoftwareupdate</string>
```

---

## Merge Strategy

The launchd plists match upstream, so upstream merges apply cleanly - no
keep-OURS handling is needed for `launchd/`.

**Verification after merge:**
```bash
git diff upstream/main -- launchd/
```

---

## Configuration Details

### ManagedSoftwareCenter LaunchAgent

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>com.googlecode.munki.ManagedSoftwareCenter</string>
    </array>
    <key>KeepAlive</key>
    <dict>
        <key>PathState</key>
        <dict>
            <key>/var/run/com.googlecode.munki.ManagedSoftwareCenter</key>
            <true/>
        </dict>
    </dict>
    <key>Label</key>
    <string>com.googlecode.munki.ManagedSoftwareCenter</string>
    <key>LimitLoadToSessionType</key>
    <array>
        <string>Aqua</string>
    </array>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/munki/libexec/launchapp</string>
        <string>-a</string>
        <string>/Applications/Managed Software Center.app</string>
    </array>
</dict>
</plist>
```

---

## Related Files

### app_usage LaunchAgent/Daemon

Located in separate directories:
- `launchd/app_usage_LaunchAgent/`
- `launchd/app_usage_LaunchDaemon/`

These are generally not customized.

---

## See Also

- [Master Customizations Index](../CUSTOMIZATIONS.md)
- [Build System Customizations](../code/tools/customizations.md)
- [Branding Customizations](../code/apps/Managed%20Software%20Center/customizations.md)
