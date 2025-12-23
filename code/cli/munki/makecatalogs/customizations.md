# makecatalogs Customizations

## Silent Mode (--silent, -q)

**Added**: December 23, 2025

### Description
Added a `--silent` / `-q` flag to suppress normal output messages during catalog generation. This is useful for automated scripts and pipelines where only errors need to be reported.

### Implementation
- Added `@Flag` property `silent` with long form `--silent` and short form `-q`
- When enabled, sets the `verbose` option to `false` in `MakeCatalogOptions`
- Warnings and errors are still printed to stderr

### Usage
```bash
# Suppress normal output
makecatalogs --silent /path/to/repo

# Using short form
makecatalogs -q /path/to/repo
```

### Use Cases
- CI/CD pipelines where clean output is desired
- Automated scripts that parse output
- Scheduled jobs where logging verbosity needs to be minimized
