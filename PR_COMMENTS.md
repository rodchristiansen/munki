From: https://github.com/munki/munki/pull/1261

arubdesu commented last week
How does this handle datetimestamps? I think that's been a barrier in the past, but I could be confusing it with JSON handling
 @rodchristiansen
Author
rodchristiansen commented last week
When Yams encounters a Swift Date object, it automatically serializes it to ISO 8601 format 2025-08-26T07:07:03.651Z and back. I believe its JSON that has no native date support and requires string parsing.
 @gregneagle
Contributor
gregneagle commented last week
Hey Rod:

You are right in guessing that I have no appetite for a PR of this size and complexity until sometime after the Munki 7 release.

In the meantime, some concerns off the top of my head:

Reliance on a third-party yaml library/package. So far, the Swift Munki has only used Swift packages from Apple. I'm vaguely uncomfortable with using third-party packages, though perhaps my discomfort is unwarranted. I worry about open source licensing and what happens if the package maintainer abandons the package or doesn't keep it otherwise maintained.
Chicken-and-egg:
admins using MunkiAdmin or MunkiWebAdmin2 (that would include me) can't really migrate to a YAML-based repo until these tools are updated to handle YAML-formated files.
You'd have to make sure every single client you have was updated to a newer version of the Munki tools before you could transition your repo
Mixed-format repos. You write "Automatic detection by file extension enables seamless mixed-format repositories. Files are processed by existing plist utilities or new YAML utilities based on their extension". But my manifest's filenames don't have extensions, and renaming them to add file extensions would break every single existing Munki client. My pkginfo files also are largely missing ".plist" extensions, but renaming them would not be disruptive.
Another question. You write "When Yams encounters a Swift Date object, it automatically serializes it to ISO 8601 format 2025-08-26T07:07:03.651Z and back.". How does yaml distinguish between a date and a string that just happens to look like an ISO 8601 formatted date? (I don't think in practice that will be a big issue with Munki, but still curious)

I'm pretty impressed with the effort made here. I'm hoping we can figure out a way to incorporate your ideas in the future, but I cannot promise this will be merged.
 @rodchristiansen
Author
rodchristiansen commented last week • 
Hi @gregneagle, thanks for reviewing the PR and feedback.
I figured Munki v7.0 feature set is locked in.
Thought I'd at least see if I could get the ball rolling on this.

- Chicken-and-Egg Problem
If the implementation approach looks sound and reasonable from your perspective, I can work on PRs for YAML support for both MunkiAdmin and MunkiWebAdmin2 first, before Munki itself adds it.

- Mixed-Format Repository Issue
Yup... I completely didn't consider manifests and pkginfo files without extensions.

How about content-based detection instead of extension-based? Check first few lines for YAML indicators such as the --- header, or a general YAML-style formatting and fallback to plist parsing if at all ambiguous?

- Date vs String Distinction
YAML behavior for date handling:

actual_date: 2024-06-20T12:00:00Z → Date object (auto-converted)
quoted_date_string: "2024-06-20T12:00:00Z" → String (explicit string)
plain_string: this-is-not-a-date → String (not date-like)
YAML auto-converts ISO 8601 patterns to Date objects UNLESS explicitly quoted.

- Third-Party Library Dependency (Yams)
Could make YAML support optional via compile-time flags? The library is self-contained with no external dependencies.

Info on it:

Maintainer: JP Simard (former Apple employee, maintains SwiftLint)
Maturity: 1,200+ stars, 6+ years active development
License: MIT (very permissive)
Usage: Used by major Swift projects including SwiftLint, Vapor
Dependencies: None beyond Swift stdlib
Size: Small and focused (just YAML parsing)
Apple Alternative: None - Apple doesn't provide YAML support
Let me know your further thoughts, thanks!
 @gregneagle
Contributor
gregneagle commented last week
I do think you'll need to do content-based detection. Possible strategies:

Just try to parse the file as one format; if it fails, try to parse as the other format (which one you try first could depend on the value of the "global YAML preference")
Read the first line of the file. If it starts with "<?xml", process as a plist. (Some testing might need to be done to see how permissive Apple's plist parsing code is; it's possible a plist can parsed without that header...)

---

## Slack Thread Discussion Summary

Bringing in info from the Slack Munki channel [thread](https://macadmins.slack.com/archives/C04QVPFGU/p1756229597312949) for context.

### Adoption Concerns
- **Kevin M. Cox**: Acknowledged the "neat idea and well thought out PR" but noted potential adoption challenges due to third-party tools that would need updates
- **Allister Banks**: Raised concerns about "widening the tent" potentially opening doors to other format requests
- **BK**: supported it as long as it remains strictly backward compatible, defaults to plist, and is reversible

### Maintainer Burden & Support Complexity
- **elios** highlighted key concerns:
  - Additional support burden and documentation duplication (similar issues seen in AutoPkg)
  - Mac admins cannot avoid plist syntax (it's everywhere in macOS for 25+ years)
  - Worry about JSON support requests following YAML request here

### YAML Technical Considerations
- **Indentation criticality**: Confirmed indentation is vital in YAML, similar to Python
- **Quoting flexibility**: Optional single/double quotes can be coded, with strong linting in makecatalogs
- **Error handling**: Enhanced makecatalogs catches YAML formatting errors effectively

### Proposed Path Forward
- **Rod's commitment**: jokingly offered to handle all future YAML-related questions and issues
- **Documentation responsibility**: Rod volunteered to help with documentation
- **Dogfooding approach**: Rod planned to use YAML implementation with his team for several months and report findings
- **Ecosystem development**: Proposed creating PRs for MunkiAdmin and MunkiWebAdmin2 YAML support first

### Key Insights
- **New admin on-ramp**: YAML could provide easier entry point for new Munki administrators
- **Ecosystem compatibility**: Need to consider broader tool ecosystem beyond core Munki tools
- **Backward compatibility**: Critical requirement for any implementation

---

## Implementation Progress Update

### Recent Commits Since PR Opening

**[85f2c55](https://github.com/rodchristiansen/munki/commit/85f2c55) - Refactor plist reading functions to use detectFileContent**
- Implements content-based file format detection
- Addresses mixed-format repository concerns

**[b71b090](https://github.com/rodchristiansen/munki/commit/b71b090) - Smarter pkginfo handling with file format detection for extensionless files**
- Enhanced handling of pkginfo files without extensions
- More robust format detection for existing repositories

**[f6c1f69](https://github.com/rodchristiansen/munki/commit/f6c1f69) - Adds parsing approach content detection instead for extensionless manifests**
- Should solve manifest file handling without requiring file extensions - tests indicate so
- Maintains compatibility with extensionless manifests and existing Munki clients

**[e9e7127](https://github.com/rodchristiansen/munki/commit/e9e7127) - Add YAML support to `makecatalogs`**
- Enhanced YAML serialization handling NSDate, NSData, URL objects
- `--yaml` command line flag for makecatalogs
- Should be fully backward compatible with existing plist/xml workflows