# Managed Software Center Customizations

**Purpose:** Documents branding and UI customizations for Managed Software Center app.

**Location:** `code/apps/Managed Software Center/`  
**Upstream:** `https://github.com/munki/munki/tree/main/code/apps/Managed%20Software%20Center`

---

## Overview

We maintain custom branding assets to display our organization's identity in the Managed Software Center application.

---

## Customized Files

### 1. Branding Images

**Location:** `Managed Software Center/Resources/WebResources/`

| File | Size | Purpose |
|------|------|---------|
| `branding.jpg` | 36KB | Primary header banner in MSC web views |
| `branding1.jpg` | 36KB | Alternate branding (category pages) |
| `branding2.jpg` | 36KB | Alternate branding (detail pages) |

**Specifications:**
- Format: JPEG
- Dimensions: (check your actual dimensions)
- Usage: Displayed at top of Software Center web interface

**To Update:**
1. Create new image matching dimensions
2. Replace file in `Resources/WebResources/`
3. Rebuild application

### 2. Application Icon

**Location:** `Managed Software Center/AppIcon.icon/`

Custom application icon displayed in:
- Dock
- Application Switcher (⌘-Tab)
- Finder
- Launchpad

**Contents:**
```
AppIcon.icon/
├── icon_16x16.png
├── icon_16x16@2x.png
├── icon_32x32.png
├── icon_32x32@2x.png
├── icon_128x128.png
├── icon_128x128@2x.png
├── icon_256x256.png
├── icon_256x256@2x.png
├── icon_512x512.png
└── icon_512x512@2x.png
```

### 3. Localized Strings

**Location:** `Managed Software Center/*.lproj/InfoPlist.strings`

Customized display names for different localizations:
- `CFBundleDisplayName` - Name shown in Finder/Dock
- `CFBundleName` - Application name

---

## Merge Strategy

**Priority:** Always keep OUR versions during upstream merges.

```bash
# During merge conflicts on branding files
git checkout --ours "code/apps/Managed Software Center/Resources/WebResources/branding*.jpg"
git checkout --ours "code/apps/Managed Software Center/AppIcon.icon/"
git add .
```

---

## Verification

After merging from upstream:

```bash
# Verify branding images are ours (check file hash or size)
ls -la "code/apps/Managed Software Center/Managed Software Center/Resources/WebResources/branding"*

# Should show our custom sizes (36KB each)
```

---

## Related Files (Not Customized)

These files are upstream-standard but may need attention:

| File | Notes |
|------|-------|
| `base.css` | Standard CSS, no customization |
| `updates.css` | Standard CSS, no customization |
| `integration.js` | Standard JS, no customization |

---

## See Also

- [Master Customizations Index](../../CUSTOMIZATIONS.md)
- [Build System Customizations](../../code/tools/customizations.md)
