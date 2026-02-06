import Foundation
import AppKit

/// Manages automatic update checking and downloading from GitHub releases
class UpdateChecker: ObservableObject {
    
    // MARK: - Configuration
    
    /// GitHub repository owner (username or organization)
    static let repoOwner = "Inv1ous"  // TODO: Replace with actual GitHub username
    
    /// GitHub repository name
    static let repoName = "PomodoroPlus"    // TODO: Replace with actual repo name if different
    
    /// Current app version from Info.plist
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    
    /// Current build number from Info.plist
    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    
    // MARK: - Published State
    
    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var releaseNotes: String?
    @Published var errorMessage: String?
    
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    
    // MARK: - Private Properties
    
    private var downloadTask: URLSessionDownloadTask?
    private(set) var downloadSession: URLSession?  // Must retain the session!
    private let fileManager = FileManager.default
    
    // MARK: - Check for Updates
    
    /// Check GitHub releases for a newer version
    func checkForUpdates(silent: Bool = false) {
        guard !isChecking else { return }
        
        isChecking = true
        errorMessage = nil
        
        let urlString = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        
        guard let url = URL(string: urlString) else {
            handleError("Invalid GitHub URL", silent: silent)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("PomodoroPlus/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                
                if let error = error {
                    self?.handleError("Network error: \(error.localizedDescription)", silent: silent)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.handleError("Invalid response", silent: silent)
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    if httpResponse.statusCode == 404 {
                        self?.handleError("No releases found", silent: silent)
                    } else {
                        self?.handleError("GitHub API error: \(httpResponse.statusCode)", silent: silent)
                    }
                    return
                }
                
                guard let data = data else {
                    self?.handleError("No data received", silent: silent)
                    return
                }
                
                self?.parseReleaseData(data, silent: silent)
            }
        }.resume()
    }
    
    private func parseReleaseData(_ data: Data, silent: Bool) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                handleError("Invalid JSON response", silent: silent)
                return
            }
            
            // Extract version (tag_name, usually "v1.0.0" or "1.0.0")
            guard let tagName = json["tag_name"] as? String else {
                handleError("No version tag found", silent: silent)
                return
            }
            
            // Remove 'v' prefix if present
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            latestVersion = version
            
            // Extract release notes
            releaseNotes = json["body"] as? String
            
            // Find the .zip asset containing the .app
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name.lowercased().hasSuffix(".zip"),
                       let downloadURLString = asset["browser_download_url"] as? String,
                       let url = URL(string: downloadURLString) {
                        downloadURL = url
                        break
                    }
                }
            }
            
            // Compare versions
            if isNewerVersion(version, than: Self.currentVersion) {
                updateAvailable = true
                if !silent {
                    showUpdateDialog()
                }
            } else {
                updateAvailable = false
                if !silent {
                    showNoUpdateDialog()
                }
            }
            
        } catch {
            handleError("Failed to parse release data: \(error.localizedDescription)", silent: silent)
        }
    }
    
    // MARK: - Version Comparison
    
    /// Compare two version strings (e.g., "1.2.3" vs "1.2.4")
    private func isNewerVersion(_ newVersion: String, than currentVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }
        
        // Pad arrays to same length
        let maxLength = max(newComponents.count, currentComponents.count)
        var newPadded = newComponents
        var currentPadded = currentComponents
        
        while newPadded.count < maxLength { newPadded.append(0) }
        while currentPadded.count < maxLength { currentPadded.append(0) }
        
        // Compare component by component
        for i in 0..<maxLength {
            if newPadded[i] > currentPadded[i] { return true }
            if newPadded[i] < currentPadded[i] { return false }
        }
        
        return false  // Versions are equal
    }
    
    // MARK: - Download and Install
    
    /// Download the update and install it
    func downloadAndInstall() {
        guard let url = downloadURL else {
            showErrorAlert("No download URL available")
            return
        }
        
        isDownloading = true
        downloadProgress = 0
        errorMessage = nil
        
        // Create and STORE the session - it must be retained for delegate callbacks to work
        let delegate = DownloadDelegate(checker: self)
        downloadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        downloadTask = downloadSession?.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    /// Cancel ongoing download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        isDownloading = false
        downloadProgress = 0
    }
    
    /// Cleanup and invalidate the current download session (if any)
    fileprivate func cleanupDownloadSession() {
        downloadTask = nil
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
    }
    
    /// Handle downloaded file
    func handleDownloadedFile(at location: URL) {
        // Note: location is now a persistent copy made by the download delegate
        downloadProgress = 1.0
        
        do {
            try installUpdate(from: location)
            // If we get here without throwing, installUpdate will show the restart alert
            // and quit the app, so we won't reach the code below
        } catch {
            isDownloading = false
            errorMessage = error.localizedDescription
            showErrorAlert("Installation failed: \(error.localizedDescription)")
        }
        
        // Clean up the persistent copy (the installUpdate method makes its own copy)
        try? FileManager.default.removeItem(at: location)
        
        // Clean up session
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
        isDownloading = false
    }
    
    /// Show an error alert to the user
    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    /// Install the downloaded update
    private func installUpdate(from zipLocation: URL) throws {
        // Create temp directory for extraction - use a location that persists after app quits
        // Using /tmp instead of NSTemporaryDirectory to ensure it survives app termination
        let tempBase = URL(fileURLWithPath: "/tmp")
        let tempDir = tempBase.appendingPathComponent("PomodoroPlus_Update_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Log file for debugging
        let logPath = tempDir.appendingPathComponent("update.log")
        
        // Copy zip to temp location
        let zipPath = tempDir.appendingPathComponent("update.zip")
        try fileManager.copyItem(at: zipLocation, to: zipPath)
        
        // Unzip using ditto (macOS built-in, handles .app bundles correctly)
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzipProcess.arguments = ["-xk", zipPath.path, tempDir.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()
        
        guard unzipProcess.terminationStatus == 0 else {
            throw NSError(domain: "UpdateChecker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract update"])
        }
        
        // Find all .app candidates (search recursively)
        // Structure: PomodoroPlus-vX.X.X.zip -> PomodoroPlus-vX.X.X (folder) -> PomodoroPlus.app
        guard let enumerator = fileManager.enumerator(
            at: tempDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "UpdateChecker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to enumerate extracted files"])    
        }
        
        var appCandidates: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app" {
                appCandidates.append(url)
            }
        }
        
        let targetBundleId = Bundle.main.bundleIdentifier
        let appBundle = appCandidates.first(where: { Bundle(url: $0)?.bundleIdentifier == targetBundleId }) ?? appCandidates.first
        
        guard let appBundle = appBundle else {
            // Log what we found for debugging
            let contents = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            let contentsList = contents?.map { $0.lastPathComponent }.joined(separator: ", ") ?? "none"
            throw NSError(domain: "UpdateChecker", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app bundle found in update. Found: \(contentsList)"])
        }
        
        // Get current app location
        guard let currentAppURL = Bundle.main.bundleURL as URL? else {
            throw NSError(domain: "UpdateChecker", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot determine current app location"])
        }
        
        // Determine destination app URL. If running from an Xcode build (DerivedData), 
        // install to /Applications to ensure the version changes persist across relaunches.
        let destinationAppURL: URL
        let currentPath = currentAppURL.path
        if currentPath.contains("/Library/Developer/Xcode/DerivedData/") || currentPath.contains("/Build/Products/") {
            destinationAppURL = URL(fileURLWithPath: "/Applications").appendingPathComponent(currentAppURL.lastPathComponent)
        } else {
            destinationAppURL = currentAppURL
        }
        
        // Check if we need admin privileges
        let destinationDir = destinationAppURL.deletingLastPathComponent()
        let needsAdmin = !fileManager.isWritableFile(atPath: destinationDir.path)
                
        // Create the update script
        // This script will:
        // 1. Wait for the parent process to exit
        // 2. Replace the app
        // 3. Launch the new app
        let script = createUpdateScript()
        
        let scriptPath = tempDir.appendingPathComponent("update.sh")
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make script executable
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        // Initialize log file
        let initialLog = """
        Update log initialized at \(Date())
        Current app: \(currentAppURL.path)
        New app source: \(appBundle.path)
        Destination: \(destinationAppURL.path)
        Needs admin: \(needsAdmin)
        
        """
        try initialLog.write(to: logPath, atomically: true, encoding: .utf8)
        
        // Show confirmation and quit
        showRestartAlert { [weak self] in
            self?.executeUpdate(
                scriptPath: scriptPath,
                appBundle: appBundle,
                destinationAppURL: destinationAppURL,
                tempDir: tempDir,
                logPath: logPath,
                needsAdmin: needsAdmin
            )
        }
    }
    
    private func createUpdateScript() -> String {
        return """
        #!/bin/bash
        
        # Update script for PomodoroPlus
        # Arguments: PARENT_PID NEW_APP DEST_APP WORK_DIR
        
        PARENT_PID="$1"
        NEW_APP="$2"
        DEST_APP="$3"
        WORK_DIR="$4"
        LOG_FILE="${WORK_DIR}/update.log"
        
        log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
        }
        
        log "=== Update script started ==="
        log "PARENT_PID: $PARENT_PID"
        log "NEW_APP: $NEW_APP"
        log "DEST_APP: $DEST_APP"
        log "WORK_DIR: $WORK_DIR"
        
        # Wait for parent process to exit
        if [[ -n "$PARENT_PID" ]] && [[ "$PARENT_PID" != "0" ]]; then
            log "Waiting for parent process $PARENT_PID to exit..."
            WAIT_COUNT=0
            while kill -0 "$PARENT_PID" 2>/dev/null; do
                sleep 0.5
                WAIT_COUNT=$((WAIT_COUNT + 1))
                if [[ $WAIT_COUNT -gt 60 ]]; then
                    log "Warning: Parent process still running after 30s, proceeding anyway"
                    break
                fi
            done
            log "Parent process exited (waited ${WAIT_COUNT} cycles)"
        fi
        
        # Extra delay to ensure file handles are released
        sleep 2
        
        # Verify source exists
        if [[ ! -d "$NEW_APP" ]]; then
            log "ERROR: Source app bundle does not exist: $NEW_APP"
            exit 1
        fi
        log "Source app verified: $NEW_APP"
        
        DEST_DIR="$(dirname "$DEST_APP")"
        BACKUP="${DEST_APP}.backup"
        
        log "Destination directory: $DEST_DIR"
        
        # Remove old backup if present
        if [[ -e "$BACKUP" ]]; then
            log "Removing old backup: $BACKUP"
            rm -rf "$BACKUP" 2>> "$LOG_FILE" || log "Warning: Could not remove old backup"
        fi
        
        # Backup current app (if exists)
        if [[ -e "$DEST_APP" ]]; then
            log "Creating backup of current app..."
            mv "$DEST_APP" "$BACKUP" 2>> "$LOG_FILE"
            if [[ $? -ne 0 ]]; then
                log "ERROR: Failed to backup current app"
                exit 1
            fi
            log "Backup created: $BACKUP"
        fi
        
        # Copy new app in place using ditto (preserves bundle structure, code signing, and extended attrs)
        log "Copying new app to destination..."
        /usr/bin/ditto "$NEW_APP" "$DEST_APP" 2>> "$LOG_FILE"
        if [[ $? -ne 0 ]]; then
            log "ERROR: Failed to copy new app"
            # Try to restore backup
            if [[ -e "$BACKUP" ]]; then
                log "Attempting to restore backup..."
                mv "$BACKUP" "$DEST_APP" 2>> "$LOG_FILE"
            fi
            exit 1
        fi
        log "App copied successfully"
        
        # Remove quarantine attribute (best-effort, not critical)
        log "Removing quarantine attribute..."
        /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" 2>> "$LOG_FILE" || log "Note: Could not remove quarantine (may not be present)"
        
        # Verify the new app exists
        if [[ ! -d "$DEST_APP" ]]; then
            log "ERROR: Destination app does not exist after copy!"
            exit 1
        fi
        log "Destination app verified"
        
        # Remove backup (cleanup)
        if [[ -e "$BACKUP" ]]; then
            log "Removing backup..."
            rm -rf "$BACKUP" 2>> "$LOG_FILE" || log "Warning: Could not remove backup"
        fi
        
        # Launch the new app
        log "Launching updated app..."
        sleep 1
        /usr/bin/open "$DEST_APP" 2>> "$LOG_FILE"
        if [[ $? -ne 0 ]]; then
            log "ERROR: Failed to launch app"
            exit 1
        fi
        log "App launched successfully"
        
        # Schedule cleanup of work directory (delay to ensure everything completes)
        log "Scheduling cleanup..."
        (sleep 10 && rm -rf "$WORK_DIR" 2>/dev/null) &
        
        log "=== Update completed successfully ==="
        exit 0
        """
    }
    
    private func executeUpdate(scriptPath: URL, appBundle: URL, destinationAppURL: URL, tempDir: URL, logPath: URL, needsAdmin: Bool) {
        let pid = ProcessInfo.processInfo.processIdentifier
        
        if needsAdmin {
            // Use AppleScript to request admin privileges and run the update script
            // Escape paths for shell within AppleScript
            let shellEscape: (String) -> String = { path in
                return path.replacingOccurrences(of: "'", with: "'\"'\"'")
            }
            
            let escapedScript = shellEscape(scriptPath.path)
            let escapedApp = shellEscape(appBundle.path)
            let escapedDest = shellEscape(destinationAppURL.path)
            let escapedWorkDir = shellEscape(tempDir.path)
            let escapedLog = shellEscape(logPath.path)
            
            // Build the shell command with proper quoting
            let shellCommand = "/bin/bash '\(escapedScript)' \(pid) '\(escapedApp)' '\(escapedDest)' '\(escapedWorkDir)'"
            
            // Escape for AppleScript string (double backslashes and quotes)
            let appleScriptCommand = shellCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            
            // Write a launcher script that will run the AppleScript after the app quits
            let launcherScript = """
            #!/bin/bash
            
            LOG_FILE="\(escapedLog)"
            
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launcher script started" >> "$LOG_FILE"
            
            # Wait for the app to quit
            sleep 3
            
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Requesting admin privileges..." >> "$LOG_FILE"
            
            # Run with admin privileges
            /usr/bin/osascript -e 'do shell script "\(appleScriptCommand)" with administrator privileges' >> "$LOG_FILE" 2>&1
            EXIT_CODE=$?
            
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] AppleScript exited with code: $EXIT_CODE" >> "$LOG_FILE"
            
            exit $EXIT_CODE
            """
            
            let launcherPath = tempDir.appendingPathComponent("launcher.sh")
            do {
                try launcherScript.write(to: launcherPath, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcherPath.path)
                
                appendToLog(logPath, message: "Admin update requested, launching admin script...")
                
                // Launch the launcher script detached from this process
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
                task.arguments = [launcherPath.path]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                task.currentDirectoryURL = tempDir
                
                // Important: Make sure the process doesn't get killed when parent dies
                task.qualityOfService = .userInitiated
                
                try task.run()
                
            } catch {
                appendToLog(logPath, message: "Failed to start admin launcher: \(error)")
            }
        } else {
            // No admin needed, run the script directly detached
            appendToLog(logPath, message: "No admin needed, running update script directly...")
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            task.arguments = [
                scriptPath.path,
                String(pid),
                appBundle.path,
                destinationAppURL.path,
                tempDir.path
            ]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            task.currentDirectoryURL = tempDir
            task.qualityOfService = .userInitiated
            
            do {
                try task.run()
            } catch {
                appendToLog(logPath, message: "Failed to start update script: \(error)")
            }
        }
        
        // Give the script a moment to start before quitting
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func appendToLog(_ logPath: URL, message: String) {
        let logMessage = "[Swift \(Date())] \(message)\n"
        if let data = logMessage.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: logPath) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }
    
    // MARK: - Error Handling
    
    private func handleError(_ message: String, silent: Bool) {
        isChecking = false
        errorMessage = message
        
        if !silent {
            let alert = NSAlert()
            alert.messageText = "Update Check Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Dialogs
    
    private func showUpdateDialog() {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Version \(latestVersion ?? "unknown") is available. You are currently running version \(Self.currentVersion).\n\nWould you like to download and install the update?"
        
        if let notes = releaseNotes, !notes.isEmpty {
            // Truncate long release notes
            let truncatedNotes = notes.count > 500 ? String(notes.prefix(500)) + "..." : notes
            alert.informativeText += "\n\nRelease Notes:\n\(truncatedNotes)"
        }
        
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            downloadAndInstall()
        case .alertThirdButtonReturn:
            // Could save skipped version to UserDefaults to not show again
            UserDefaults.standard.set(latestVersion, forKey: "skippedVersion")
        default:
            break
        }
    }
    
    private func showNoUpdateDialog() {
        let alert = NSAlert()
        alert.messageText = "No Updates Available"
        alert.informativeText = "You are running the latest version (\(Self.currentVersion))."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showRestartAlert(onConfirm: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Ready to Install Update"
        alert.informativeText = "The app will quit and restart to complete the update. Make sure to save any work before continuing.\n\nYou may be asked for your administrator password."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            onConfirm()
        }
    }
    
    // MARK: - Auto-Check on Startup
    
    /// Check for updates silently on app startup
    func checkOnStartup() {
        // Check if user has skipped this version
        let skippedVersion = UserDefaults.standard.string(forKey: "skippedVersion")
        
        // Perform silent check
        checkForUpdates(silent: true)
        
        // After check completes, show dialog if update is available and not skipped
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            
            if self.updateAvailable,
               let latest = self.latestVersion,
               latest != skippedVersion {
                self.showUpdateDialog()
            }
        }
    }
    
    // MARK: - Debug Helpers
    
    /// Open the most recent update log file (for debugging failed updates)
    func openUpdateLog() {
        let tempBase = URL(fileURLWithPath: "/tmp")
        let fm = FileManager.default
        
        // Find update directories
        guard let contents = try? fm.contentsOfDirectory(at: tempBase, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            showNoLogDialog()
            return
        }
        
        // Find the most recent update log
        let updateDirs = contents.filter { $0.lastPathComponent.hasPrefix("PomodoroPlus_Update_") }
        
        var latestLog: URL?
        var latestDate: Date?
        
        for dir in updateDirs {
            let logFile = dir.appendingPathComponent("update.log")
            if let attrs = try? fm.attributesOfItem(atPath: logFile.path),
               let modDate = attrs[.modificationDate] as? Date {
                if latestDate == nil || modDate > latestDate! {
                    latestDate = modDate
                    latestLog = logFile
                }
            }
        }
        
        if let log = latestLog {
            NSWorkspace.shared.open(log)
        } else {
            showNoLogDialog()
        }
    }
    
    private func showNoLogDialog() {
        let alert = NSAlert()
        alert.messageText = "No Update Log Found"
        alert.informativeText = "No recent update logs were found. Logs are created when an update is attempted."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var checker: UpdateChecker?
    
    init(checker: UpdateChecker) {
        self.checker = checker
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // CRITICAL: The file at `location` is temporary and will be deleted
        // as soon as this method returns. We MUST copy it synchronously before returning.
        
        let fileManager = FileManager.default
        
        // Use the app's own temporary directory first (works in both sandboxed and non-sandboxed).
        // Fall back to /tmp if that fails for any reason.
        let primaryTempDir = fileManager.temporaryDirectory
        let fallbackTempDir = URL(fileURLWithPath: "/tmp")
        
        let fileName = "PomodoroPlus_download_\(UUID().uuidString).zip"
        let primaryLocation = primaryTempDir.appendingPathComponent(fileName)
        let fallbackLocation = fallbackTempDir.appendingPathComponent(fileName)
        
        var persistentLocation: URL?
        var lastError: Error?
        
        // Try primary location (app temp dir)
        do {
            try fileManager.copyItem(at: location, to: primaryLocation)
            persistentLocation = primaryLocation
        } catch {
            lastError = error
            // Try fallback location (/tmp)
            do {
                try fileManager.copyItem(at: location, to: fallbackLocation)
                persistentLocation = fallbackLocation
            } catch {
                lastError = error
            }
        }
        
        if let persistentLocation = persistentLocation {
            DispatchQueue.main.async { [weak self] in
                self?.checker?.handleDownloadedFile(at: persistentLocation)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.checker?.isDownloading = false
                self?.checker?.cleanupDownloadSession()
                
                let alert = NSAlert()
                alert.messageText = "Download Error"
                alert.informativeText = "Failed to save downloaded file: \(lastError?.localizedDescription ?? "Unknown error")\n\nThis is usually caused by App Sandbox being enabled. Please ensure ENABLE_APP_SANDBOX is set to NO in Xcode build settings."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            // Unknown total size (e.g., chunked transfer). Advance slowly to show activity.
            let current = self.checker?.downloadProgress ?? 0
            progress = min(0.95, current + 0.005)
        }
        DispatchQueue.main.async { [weak self] in
            self?.checker?.downloadProgress = max(0.0, min(1.0, progress))
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in
                self?.checker?.isDownloading = false
                self?.checker?.cleanupDownloadSession()
                
                // Don't show error for cancellation
                if (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                
                let alert = NSAlert()
                alert.messageText = "Download Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}

