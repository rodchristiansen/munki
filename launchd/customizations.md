# Launchd Configuration Customizations

**Purpose:** Documents customizations to launchd property lists for Munki services.

**Location:** `launchd/`  
**Upstream:** `https://github.com/munki/munki/tree/main/launchd`

---

## Overview

We maintain customized launchd plists that differ from upstream primarily in:
- Application paths (we use "Software Center" naming)
- AssociatedBundleIdentifiers for macOS notification handling
- Tool paths (`/usr/local/munki/libexec/` structure)

---

## Customized Files

### LaunchAgents (User Context)

| File | Purpose | Key Customizations |
|------|---------|-------------------|
| `com.googlecode.munki.ManagedSoftwareCenter.plist` | Triggers Software Center launch | Path to `Software Center.app`, libexec paths |
| `com.googlecode.munki.MunkiStatus.plist` | Status display during installs | Path to MunkiStatus within Software Center.app |
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

```diff
- /Applications/Managed Software Center.app
+ /Applications/Software Center.app
```

We use "Software Center" as the user-facing application name.

### 2. Tool Paths

```diff
- /usr/local/munki/launchapp
+ /usr/local/munki/libexec/launchapp
```

Internal tools moved to `libexec/` subdirectory per Munki 7 structure.

### 3. PathState Triggers

```diff
- /var/run/com.googlecode.munki.ManagedSoftwareCenter
+ /var/run/com.googlecode.munki.SoftwareCenter
```

Updated to match our application naming.

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

**Priority:** Always keep OUR versions during upstream merges.

```bash
# During merge conflicts
git checkout --ours launchd/
git add launchd/
```

**Verification after merge:**
```bash
# Check our paths are preserved
grep -r "Software Center" launchd/
# Should show multiple matches

# Verify libexec paths
grep -r "libexec" launchd/
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
            <key>/var/run/com.googlecode.munki.SoftwareCenter</key>
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
        <string>/Applications/Software Center.app</string>
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
