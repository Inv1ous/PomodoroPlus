import Foundation
import AppKit

/// Manages automatic update checking and downloading from GitHub releases
class UpdateChecker: ObservableObject {
    
    // MARK: - Configuration
    
    /// GitHub repository owner (username or organization)
    static let repoOwner = "Inv1ous"  // TODO: Replace with actual GitHub username
    
    /// GitHub repository name
    static let repoName = "AntiDisturbPomodoro"    // TODO: Replace with actual repo name if different
    
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
        request.setValue("AntiDisturbPomodoro/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
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
            errorMessage = "No download URL available"
            return
        }
        
        isDownloading = true
        downloadProgress = 0
        
        let session = URLSession(configuration: .default, delegate: DownloadDelegate(checker: self), delegateQueue: nil)
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    /// Cancel ongoing download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadProgress = 0
    }
    
    /// Handle downloaded file
    func handleDownloadedFile(at location: URL) {
        DispatchQueue.main.async { [weak self] in
            self?.isDownloading = false
            self?.downloadProgress = 1.0
            
            do {
                try self?.installUpdate(from: location)
            } catch {
                self?.errorMessage = "Installation failed: \(error.localizedDescription)"
            }
        }
    }
    
    /// Install the downloaded update
    private func installUpdate(from zipLocation: URL) throws {
        // Create temp directory for extraction
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("AntiDisturbPomodoro_Update_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
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
        
        // Find the .app bundle in extracted contents
        let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "UpdateChecker", code: 2, userInfo: [NSLocalizedDescriptionKey: "No .app bundle found in update"])
        }
        
        // Get current app location
        guard let currentAppURL = Bundle.main.bundleURL as URL? else {
            throw NSError(domain: "UpdateChecker", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot determine current app location"])
        }
        
        // Verify the new app is signed and valid (optional but recommended)
        // For now, we'll proceed with installation
        
        // Create a script to replace the app and relaunch
        let script = """
        #!/bin/bash
        sleep 2
        rm -rf "\(currentAppURL.path)"
        cp -R "\(appBundle.path)" "\(currentAppURL.path)"
        open "\(currentAppURL.path)"
        rm -rf "\(tempDir.path)"
        """
        
        let scriptPath = tempDir.appendingPathComponent("update.sh")
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make script executable
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        
        // Show confirmation and quit
        showRestartAlert {
            // Run the update script in background
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scriptPath.path]
            task.standardOutput = nil
            task.standardError = nil
            try? task.run()
            
            // Quit the app
            NSApplication.shared.terminate(nil)
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
        alert.informativeText = "The app will quit and restart to complete the update. Make sure to save any work before continuing."
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
}

// MARK: - Download Delegate

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var checker: UpdateChecker?
    
    init(checker: UpdateChecker) {
        self.checker = checker
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        checker?.handleDownloadedFile(at: location)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            self?.checker?.downloadProgress = progress
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in
                self?.checker?.isDownloading = false
                self?.checker?.errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }
}
