//
//  munkiimport.swift
//  munki
//
//  Created by Greg Neagle on 7/12/24.
//
//  Copyright 2024-2025 Greg Neagle.
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

import ArgumentParser
import Foundation
import MunkiShared

// MARK: - Git Integration Functions

/// Check if the given path is inside a git repository
func isGitRepository(_ path: String) -> Bool {
    var currentPath = path
    let fileManager = FileManager.default
    
    // Walk up the directory tree looking for .git folder
    while currentPath != "/" {
        let gitPath = (currentPath as NSString).appendingPathComponent(".git")
        if fileManager.fileExists(atPath: gitPath) {
            return true
        }
        currentPath = (currentPath as NSString).deletingLastPathComponent
    }
    return false
}

/// Run git pull in the specified directory with smart conflict handling
func runGitPull(repoPath: String) -> Bool {
    print("Git repository detected, pulling latest changes before import...")
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    task.arguments = ["pull"]
    task.currentDirectoryURL = URL(fileURLWithPath: repoPath)
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = errorPipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let stdoutText = String(data: outputData, encoding: .utf8) ?? ""
        let stderrText = String(data: errorData, encoding: .utf8) ?? ""
        
        if !stdoutText.isEmpty {
            print(stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        if task.terminationStatus == 0 {
            print("Git pull completed successfully")
            return true
        } else {
            // Check if failure is due to merge conflicts or divergent branches
            let conflictIndicators = [
                "CONFLICT",
                "Automatic merge failed",
                "divergent branches",
                "Please commit your changes",
                "have diverged"
            ]
            
            let hasConflicts = conflictIndicators.contains { indicator in
                stdoutText.contains(indicator) || stderrText.contains(indicator)
            }
            
            if hasConflicts {
                print("Git pull failed with conflicts, attempting rebase with autostash...")
                
                // Try git pull with rebase and autostash
                let rebaseTask = Process()
                rebaseTask.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                rebaseTask.arguments = ["pull", "--rebase", "--autostash"]
                rebaseTask.currentDirectoryURL = URL(fileURLWithPath: repoPath)
                
                let rebaseOutputPipe = Pipe()
                let rebaseErrorPipe = Pipe()
                rebaseTask.standardOutput = rebaseOutputPipe
                rebaseTask.standardError = rebaseErrorPipe
                
                try rebaseTask.run()
                rebaseTask.waitUntilExit()
                
                let rebaseOutputData = rebaseOutputPipe.fileHandleForReading.readDataToEndOfFile()
                let rebaseErrorData = rebaseErrorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let rebaseStdoutText = String(data: rebaseOutputData, encoding: .utf8) ?? ""
                let rebaseStderrText = String(data: rebaseErrorData, encoding: .utf8) ?? ""
                
                if rebaseTask.terminationStatus == 0 {
                    if !rebaseStdoutText.isEmpty {
                        print(rebaseStdoutText.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    print("Git pull with rebase completed successfully")
                    return true
                } else {
                    printStderr("Git pull with rebase also failed: \(rebaseStderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
                    print("Continuing with import anyway...")
                    return false
                }
            } else {
                if !stderrText.isEmpty {
                    printStderr("Git pull failed: \(stderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                print("Continuing with import anyway...")
                return false
            }
        }
    } catch {
        printStderr("Error running git pull: \(error)")
        print("Continuing with import...")
        return false
    }
}

// MARK: - Repo Path Helper Functions

/// Get the full absolute path to the repo root from URL
func getRepoRootPath(from repoURL: String, repo: Repo) -> String? {
    if let filerepo = repo as? FileRepo {
        return filerepo.root
    }
    
    // Try to parse file:// URL
    if repoURL.hasPrefix("file://") {
        if let url = URL(string: repoURL) {
            return url.path
        }
    }
    
    return nil
}

// MARK: - Filename Sanitization Functions

/// Sanitize the installer item filename with architecture suffix
func sanitizeInstallerFilename(originalPath: String, pkginfo: PlistDict) -> String {
    let fileManager = FileManager.default
    let fileExtension = (originalPath as NSString).pathExtension
    let baseExtension = fileExtension.isEmpty ? "" : ".\(fileExtension)"
    
    // Get name and version from pkginfo
    guard let name = pkginfo["name"] as? String,
          let version = pkginfo["version"] as? String else {
        return originalPath
    }
    
    // Remove spaces from name
    var sanitizedName = name.replacingOccurrences(of: " ", with: "")
    
    // Add version if not already in the name
    let versionWithoutSpaces = version.replacingOccurrences(of: " ", with: "")
    if !sanitizedName.contains("-\(versionWithoutSpaces)") {
        sanitizedName += "-\(versionWithoutSpaces)"
    }
    
    // Add architecture suffix based on supported_architectures
    if let architectures = pkginfo["supported_architectures"] as? [String] {
        if architectures == ["arm64"] {
            sanitizedName += "-Apple"
        } else if architectures == ["x86_64"] {
            sanitizedName += "-Intel"
        }
        // Multiple or other architectures get no suffix
    }
    
    // Add back the file extension
    sanitizedName += baseExtension
    
    // Build the new path in the same directory
    let originalDirectory = (originalPath as NSString).deletingLastPathComponent
    let sanitizedPath = (originalDirectory as NSString).appendingPathComponent(sanitizedName)
    
    return sanitizedPath
}

/// Rename installer item with read-only filesystem handling
func renameInstallerItem(from sourcePath: String, to destinationPath: String) -> String {
    let fileManager = FileManager.default
    
    // If source and destination are the same, no need to rename
    if sourcePath == destinationPath {
        return sourcePath
    }
    
    do {
        // Remove destination if it already exists
        if fileManager.fileExists(atPath: destinationPath) {
            try fileManager.removeItem(atPath: destinationPath)
        }
        
        try fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
        let sanitizedName = (destinationPath as NSString).lastPathComponent
        print("Renamed to \(sanitizedName)")
        return destinationPath
    } catch let error as NSError {
        // Check for read-only filesystem error (EROFS = 30)
        if error.code == 30 || error.domain == NSCocoaErrorDomain && error.code == NSFileWriteVolumeReadOnlyError {
            print("Skipping rename on read-only filesystem...")
            return sourcePath
        } else {
            printStderr("Warning: Could not rename file: \(error.localizedDescription)")
            return sourcePath
        }
    }
}

@main
struct MunkiImport: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "munkiimport",
        abstract: "Imports an item into a Munki repo"
    )

    @OptionGroup(title: "MunkiImport Options")
    var munkiImportOptions: MunkiImportOptions

    @OptionGroup(title: "Pkginfo Override Options")
    var overrideOptions: OverrideOptions

    @OptionGroup(title: "Script Options")
    var scriptOptions: ScriptOptions

    @OptionGroup(title: "Drag-n-drop Disk Image Options")
    var dmgOptions: DragNDropOptions

    @OptionGroup(title: "Installer Package Options")
    var packageOptions: ApplePackageOptions

    @OptionGroup(title: "Forced/Unattended Options")
    var unattendedOptions: UnattendedInstallOptions

    @OptionGroup(title: "Generating 'installs' Items")
    var installsOptions: GeneratingInstallsOptions

    @OptionGroup(title: "Installer Types")
    var installerTypeOptions: InstallerTypeOptions

    @OptionGroup(title: "Additional Options")
    var additionalOptions: AdditionalPkginfoOptions

    @OptionGroup(visibility: .private)
    var hiddenOptions: HiddenPkginfoOptions

    @Argument(help: ArgumentHelp(
        "Path to installer item (package or disk image).",
        valueName: "installer-item"
    ))
    var installerItem = ""

    mutating func validate() throws {
        if munkiImportOptions.version {
            return
        }

        if munkiImportOptions.configure {
            return
        }

        // validate repoURL
        if munkiImportOptions.repoURL == nil {
            munkiImportOptions.repoURL = adminPref("repo_url") as? String? ?? nil
        }
        if munkiImportOptions.repoURL == nil ||
            munkiImportOptions.repoURL == ""
        {
            throw ValidationError("No repo URL found. Please run this tool with the --configure option, or use the --repo-url option.")
        }

        // validate installerItem
        if installerItem.isEmpty {
            throw ValidationError("Missing expected argument '<installer-item>'")
        }
        if installerItem.last == "/" {
            installerItem.removeLast()
        }
        if !hasValidInstallerItemExt(installerItem),
           !isApplication(installerItem)
        {
            throw ValidationError("Installer item '\(installerItem)' does not appear to be of a supported type.")
        }
        if hasValidDiskImageExt(installerItem),
           pathIsDirectory(installerItem)
        {
            // a directory named with .dmg or .iso extension. Let"s bail
            throw ValidationError("Installer item '\(installerItem)' does not appear to be of a supported type.")
        }
        if !FileManager.default.fileExists(atPath: installerItem) {
            throw ValidationError("Installer item '\(installerItem)' does not exist!")
        }
    }

    mutating func run() async throws {
        if munkiImportOptions.version {
            print(getVersion())
            return
        }

        // install handlers for SIGINT and SIGTERM
        let sigintSrc = installSignalHandler(SIGINT, cleanUpFunction: cleanupReadline)
        sigintSrc.activate()
        let sigtermSrc = installSignalHandler(SIGTERM, cleanUpFunction: cleanupReadline)
        sigtermSrc.activate()

        if munkiImportOptions.configure {
            let promptList = [
                ("repo_url", "Repo URL (example: afp://munki.example.com/repo)"),
                ("pkginfo_extension", "pkginfo extension (Example: .plist)"),
                ("editor", "pkginfo editor (examples: /usr/bin/vi or TextMate.app; leave empty to not open an editor after import)"),
                ("default_catalog", "Default catalog to use (example: testing)"),
                ("plugin", "Repo access plugin (defaults to FileRepo)"),
            ]
            configure(promptList: promptList)
            return
        }

        var pkginfoOptions = PkginfoOptions(
            override: overrideOptions,
            script: scriptOptions,
            dmg: dmgOptions,
            pkg: packageOptions,
            force: unattendedOptions,
            installs: installsOptions,
            type: installerTypeOptions,
            other: additionalOptions,
            hidden: hiddenOptions
        )

        if pathIsDirectory(installerItem) {
            let dmgPath = makeDmg(installerItem)
            if !dmgPath.isEmpty {
                installerItem = dmgPath
            } else {
                printStderr("Could not convert \(installerItem) to a disk image.")
                throw ExitCode(-1)
            }
        }

        if let uninstallerItem = pkginfoOptions.pkg.uninstalleritem,
           pathIsDirectory(uninstallerItem)
        {
            let dmgPath = makeDmg(uninstallerItem)
            if !dmgPath.isEmpty {
                pkginfoOptions.pkg.uninstalleritem = dmgPath
            } else {
                printStderr("Could not convert \(uninstallerItem) to a disk image.")
                throw ExitCode(-1)
            }
        }

        guard let repoURL = munkiImportOptions.repoURL,
              let plugin = munkiImportOptions.plugin
        else {
            // won"t happen because we validated it earlier
            throw ExitCode(1)
        }

        // make a pkginfo
        print("Analyzing installer item...")
        var pkginfo: PlistDict
        do {
            pkginfo = try makepkginfo(installerItem, options: pkginfoOptions)
        } catch let error as MunkiError {
            printStderr("ERROR: \(error.description)")
            throw ExitCode(-1)
        } catch {
            printStderr("Unexpected error: \(type(of: error))")
            printStderr(error)
            throw ExitCode(-1)
        }

        // connect to the repo
        var repo: Repo
        do {
            repo = try repoConnect(url: repoURL, plugin: plugin)
        } catch let error as MunkiError {
            printStderr("Repo connection error: \(error.description)")
            throw ExitCode(-1)
        }

        // Run git pull if this is a git repository (FileRepo only)
        if let filerepo = repo as? FileRepo {
            let repoRoot = filerepo.root
            if isGitRepository(repoRoot) {
                let _ = runGitPull(repoPath: repoRoot)
            }
        }

        // Run makecatalogs silently to refresh catalog state before import
        print("Refreshing catalog state...")
        let makecatalogOptions = MakeCatalogOptions(verbose: false)
        do {
            var catalogsmaker = try await CatalogsMaker(repo: repo, options: makecatalogOptions)
            await catalogsmaker.makecatalogs()
            if !catalogsmaker.errors.isEmpty {
                print("Warning: Issues occurred while refreshing catalogs before import.")
            }
        } catch {
            // Continue even if makecatalogs fails
            print("Warning: Could not refresh catalogs before import.")
        }

        if !munkiImportOptions.nointeractive {
            // try to find existing pkginfo items that match this one
            if let matchingPkgInfo = await findMatchingPkginfo(repo, pkginfo) {
                var exactMatch = false
                if let matchingItemHash = matchingPkgInfo["installer_item_hash"] as? String,
                   let ourItemHash = pkginfo["installer_item_hash"] as? String,
                   matchingItemHash == ourItemHash
                {
                    exactMatch = true
                    print("***This item is identical to an existing item in the repo***:")
                } else {
                    print("This item is similar to an existing item in the repo:")
                }
                let fields = [
                    ("Item name", "name"),
                    ("Display name", "display_name"),
                    ("Description", "description"),
                    ("Version", "version"),
                    ("Installer item path", "installer_item_location"),
                    ("Catalogs", "catalogs"),
                ]
                for (name, key) in fields {
                    if key == "catalogs" {
                        if let catalogs = matchingPkgInfo[key] as? [String] {
                            let catalogsString = catalogs.joined(separator: ", ")
                            print("\(leftPad(name, 21)): \(catalogsString)")
                        }
                    } else if let value = matchingPkgInfo[key] as? String {
                        print("\(leftPad(name, 21)): \(value)")
                    }
                }
                print()
                if exactMatch {
                    print("Import this item anyway? y/N] ", terminator: "")
                    if let answer = readLine(),
                       !answer.lowercased().hasPrefix("y")
                    {
                        return
                    }
                }
                print("Use existing item as a template? [y/N] ", terminator: "")
                if let answer = readLine(),
                   answer.lowercased().hasPrefix("y")
                {
                    // copy some info from the matchingPkgInfo
                    if let matchingDisplayName = matchingPkgInfo["display_name"] as? String {
                        pkginfo["display_name"] = matchingDisplayName
                    } else if pkginfo["display_name"] == nil {
                        pkginfo["display_name"] = matchingPkgInfo["name"]
                    }
                    if pkginfo["description"] == nil {
                        pkginfo["description"] = matchingPkgInfo["description"]
                    }
                    // if a subdirectory hasn't been specified, use the same one as the
                    // matching pkginfo
                    if munkiImportOptions.subdirectory == nil,
                       let matchingInstallLocation = matchingPkgInfo["installer_item_location"] as? String
                    {
                        munkiImportOptions.subdirectory = (matchingInstallLocation as NSString).deletingLastPathComponent
                    }
                    for (key, kind) in [
                        ("name", "String"),
                        ("blocking_applications", "StringArray"),
                        ("forced_install", "Bool"),
                        ("forced_uninstall", "Bool"),
                        ("unattended_install", "Bool"),
                        ("unattended_uninstall", "Bool"),
                        ("requires", "StringArray"),
                        ("update_for", "StringArray"),
                        ("category", "String"),
                        ("developer", "String"),
                        ("icon_name", "String"),
                        ("unused_software_removal_info", "Dict"),
                        ("localized_strings", "Dict"),
                        ("featured", "Bool"),
                        ("preinstall_script", "String"),
                        ("postinstall_script", "String"),
                        ("installcheck_script", "String"),
                        ("uninstallcheck_script", "String"),
                        ("postuninstall_script", "String"),
                        ("uninstall_script", "String"),
                    ] {
                        if let matchingKeyValue = matchingPkgInfo[key] {
                            switch kind {
                            case "Bool":
                                let value = String(matchingKeyValue as? Bool ?? false).capitalized
                                print("Copying \(key): \(value)")
                            case "String":
                                if key.hasSuffix("_script") {
                                    // Don't print the full script content, just note it was copied
                                    print("Copying \(key)")
                                } else {
                                    print("Copying \(key): \(matchingKeyValue)")
                                }
                            default:
                                print("Copying \(key): \(matchingKeyValue)")
                            }
                            pkginfo[key] = matchingKeyValue
                        }
                    }
                    
                    // Handle installs array - copy path values from matching items
                    if let matchingInstalls = matchingPkgInfo["installs"] as? [[String: Any]],
                       let currentInstalls = pkginfo["installs"] as? [[String: Any]],
                       matchingInstalls.count == currentInstalls.count {
                        var updatedInstalls = currentInstalls
                        for (index, var install) in updatedInstalls.enumerated() {
                            if let matchingPath = matchingInstalls[index]["path"] as? String {
                                install["path"] = matchingPath
                                updatedInstalls[index] = install
                            }
                        }
                        pkginfo["installs"] = updatedInstalls
                    }
                    
                    // Handle items_to_copy array - copy destination_path values from matching items
                    if let matchingItemsToCopy = matchingPkgInfo["items_to_copy"] as? [[String: Any]],
                       let currentItemsToCopy = pkginfo["items_to_copy"] as? [[String: Any]],
                       matchingItemsToCopy.count == currentItemsToCopy.count {
                        var updatedItemsToCopy = currentItemsToCopy
                        for (index, var item) in updatedItemsToCopy.enumerated() {
                            if let matchingDestPath = matchingItemsToCopy[index]["destination_path"] as? String {
                                item["destination_path"] = matchingDestPath
                                updatedItemsToCopy[index] = item
                            }
                        }
                        pkginfo["items_to_copy"] = updatedItemsToCopy
                    }
                }
            }
            // now let user do some basic editing
            let editfields = [
                ("Item name", "name", "String"),
                ("Display name", "display_name", "String"),
                ("Description", "description", "String"),
                ("Version", "version", "String"),
                ("Category", "category", "String"),
                ("Developer", "developer", "String"),
                ("Unattended install", "unattended_install", "Bool"),
                ("Unattended uninstall", "unattended_uninstall", "Bool"),
                ("Architecture(s)", "supported_architectures", "StringArray"),
            ]
            for (name, key, kind) in editfields {
                let prompt = leftPad(name, 20) + ": "
                var defaultValue = ""
                if kind == "Bool" {
                    defaultValue = String(pkginfo[key] as? Bool ?? false).capitalized
                } else if kind == "StringArray" {
                    if let array = pkginfo[key] as? [String] {
                        defaultValue = array.joined(separator: ", ")
                    } else {
                        defaultValue = "x86_64, arm64"
                    }
                } else {
                    defaultValue = pkginfo[key] as? String ?? ""
                }
                if let newValue = getInput(prompt: prompt, defaultText: defaultValue) {
                    if kind == "Bool" {
                        pkginfo[key] = newValue.lowercased().hasPrefix("t")
                    } else if kind == "StringArray" {
                        pkginfo[key] = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    } else {
                        pkginfo[key] = newValue
                    }
                }
            }
            // special handling for catalogs
            let prompt = leftPad("Catalogs", 20) + ": "
            let catalogs = pkginfo["catalogs"] as? [String] ?? ["testing"]
            let defaultValue = catalogs.joined(separator: ",")
            if let newValue = getInput(prompt: prompt, defaultText: defaultValue) {
                pkginfo["catalogs"] = newValue.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            }
            // warn if no 'is installed' criteria
            let installerType = pkginfo["installer_type"] as? String ?? ""
            if installerType != "startosinstall",
               !pkginfo.keys.contains("receipts"),
               !pkginfo.keys.contains("installs")
            {
                printStderr("WARNING: There are no receipts and no 'installs' items for this installer item. You should add at least one item to the 'installs' list, or add an installcheck_script.")
            }
            // Confirm import post-edit
            print("\nImport this item? [y/N] ", terminator: "")
            if let answer = readLine(),
               !answer.lowercased().hasPrefix("y")
            {
                return
            }
            // adjust subdir if needed
            if munkiImportOptions.subdirectory == nil,
               let filerepo = repo as? FileRepo
            {
                let repoPkgsDir = (filerepo.root as NSString).appendingPathComponent("pkgs") + "/"
                let installerItemAbsPath = getAbsolutePath(installerItem)
                if installerItemAbsPath.hasPrefix(repoPkgsDir) {
                    // super special case:
                    // We're using a file repo and the item being "imported"
                    // is actually already in the repo -- we're just creating
                    // a pkginfo item and copying it to the repo.
                    // In this case, we want to use the same subdirectory for
                    // the pkginfo that corresponds to the one the pkg is
                    // already in.
                    // We aren't handling the case of alternate implementations
                    // of FileRepo-like repos.
                    let installerItemDirPath = (installerItemAbsPath as NSString).deletingLastPathComponent
                    let startIndex = installerItemDirPath.index(installerItemDirPath.startIndex, offsetBy: repoPkgsDir.count)
                    munkiImportOptions.subdirectory = String(installerItemDirPath[startIndex...])
                }
            }
            munkiImportOptions.subdirectory = await promptForSubdirectory(repo, munkiImportOptions.subdirectory)
        }
        // if we have an icon, upload it
        if let iconPath = munkiImportOptions.iconPath,
           let name = pkginfo["name"] as? String
        {
            do {
                let _ = try await convertAndInstallIcon(repo, name: name, iconPath: iconPath)
            } catch let error as MunkiError {
                printStderr("Error importing \(iconPath): \(error.description)")
            }
        } else if !munkiImportOptions.extractIcon,
                  await !iconIsInRepo(repo, pkginfo: pkginfo)
        {
            print("No existing product icon found.")
            print("Attempt to create a product icon? [y/N] ", terminator: "")
            if let answer = readLine(),
               answer.lowercased().hasPrefix("y")
            {
                munkiImportOptions.extractIcon = true
            }
        }
        if munkiImportOptions.extractIcon {
            print("Attempting to extract and upload icon...")
            do {
                let importedPaths = try await extractAndCopyIcon(repo, installerItem: installerItem, pkginfo: pkginfo)
                if !importedPaths.isEmpty {
                    print("Imported " + importedPaths.joined(separator: ", "))
                } else {
                    print("No icons found for import.")
                }
            } catch let error as MunkiError {
                printStderr("Error importing icons: \(error.description)")
            } catch {
                printStderr("Error importing icons: \(error)")
            }
        }
        // Sanitize the installer item filename (remove spaces, add architecture suffix)
        let sanitizedInstallerPath = sanitizeInstallerFilename(originalPath: installerItem, pkginfo: pkginfo)
        let finalInstallerPath = renameInstallerItem(from: installerItem, to: sanitizedInstallerPath)
        
        // copy the installerItem to the repo
        var uploadedPkgPath = ""
        let subdir = munkiImportOptions.subdirectory ?? ""
        do {
            let installerItemName = (finalInstallerPath as NSString).lastPathComponent
            print("Copying \(installerItemName) to repo...")
            let version = pkginfo["version"] as? String ?? "UNKNOWN"
            uploadedPkgPath = try await copyInstallerItemToRepo(repo, itempath: finalInstallerPath, version: version, subdirectory: subdir)
            print("Copied \(installerItemName) to \(uploadedPkgPath).")
        } catch let error as MunkiError {
            printStderr("Error importing \(installerItem): \(error.description)")
            throw ExitCode(-1)
        } catch {
            printStderr("Error importing \(installerItem): \(error)")
            throw ExitCode(-1)
        }
        // adjust the pkginfo installer_item_location with actual location/identifier
        pkginfo["installer_item_location"] = (uploadedPkgPath as NSString).pathComponents[1...].joined(separator: "/")
        // If there's an uninstaller_item, upload that
        if let uninstallerItem = pkginfoOptions.pkg.uninstalleritem {
            // Sanitize the uninstaller item filename as well
            let sanitizedUninstallerPath = sanitizeInstallerFilename(originalPath: uninstallerItem, pkginfo: pkginfo)
            let finalUninstallerPath = renameInstallerItem(from: uninstallerItem, to: sanitizedUninstallerPath)
            
            do {
                let uninstallerItemName = (finalUninstallerPath as NSString).lastPathComponent
                print("Copying \(uninstallerItemName) to repo...")
                let version = pkginfo["version"] as? String ?? "UNKNOWN"
                uploadedPkgPath = try await copyInstallerItemToRepo(repo, itempath: finalUninstallerPath, version: version, subdirectory: subdir)
                print("Copied \(uninstallerItemName) to \(uploadedPkgPath).")
            } catch let error as MunkiError {
                printStderr("Error importing \(uninstallerItem): \(error.description)")
                throw ExitCode(-1)
            } catch {
                printStderr("Error importing \(uninstallerItem): \(error)")
                throw ExitCode(-1)
            }
            // adjust the pkginfo uninstaller_item_location with actual location/identifier
            pkginfo["uninstaller_item_location"] = (uploadedPkgPath as NSString).pathComponents[1...].joined(separator: "/")
        }
        // One last chance to edit the pkginfo
        if !munkiImportOptions.nointeractive {
            pkginfo = editPkgInfoInExternalEditor(pkginfo)
        }
        // Now upload pkginfo
        var pkginfoPath = ""
        do {
            pkginfoPath = try await copyPkgInfoToRepo(repo, pkginfo: pkginfo, subdirectory: subdir, yamlOutput: munkiImportOptions.shouldUseYaml)
            
            // Display full absolute path if available (FileRepo only)
            if let repoRoot = getRepoRootPath(from: repoURL, repo: repo) {
                let fullPath = (repoRoot as NSString).appendingPathComponent(pkginfoPath)
                print("Saved pkginfo to: \(fullPath)")
            } else {
                print("Saved pkginfo to \(pkginfoPath).")
            }
        }
        // Maybe rebuild the catalogs?
        if !munkiImportOptions.nointeractive {
            print("Rebuild catalogs? [y/N] ", terminator: "")
            if let answer = readLine(),
               answer.lowercased().hasPrefix("y")
            {
                let makecatalogOptions = MakeCatalogOptions()
                var catalogsmaker = try await CatalogsMaker(repo: repo, options: makecatalogOptions)
                await catalogsmaker.makecatalogs()
                if !catalogsmaker.errors.isEmpty {
                    for error in catalogsmaker.errors {
                        printStderr(error)
                    }
                }
            }
        }
    }
}
