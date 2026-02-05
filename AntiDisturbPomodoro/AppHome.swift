import Foundation
import AppKit

/// Manages the application's home directory structure in ~/Library/Application Support/
class AppHome: ObservableObject {
    
    static let appName = "AntiDisturbPomodoro"
    
    // MARK: - Directory URLs
    
    var rootURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Self.appName, isDirectory: true)
    }
    
    var profilesURL: URL {
        rootURL.appendingPathComponent("profiles", isDirectory: true)
    }
    
    var soundsURL: URL {
        rootURL.appendingPathComponent("sounds", isDirectory: true)
    }
    
    var importedSoundsURL: URL {
        soundsURL.appendingPathComponent("imported", isDirectory: true)
    }
    
    var soundLibraryURL: URL {
        soundsURL.appendingPathComponent("library.json")
    }
    
    var statsURL: URL {
        rootURL.appendingPathComponent("stats", isDirectory: true)
    }
    
    var statsFileURL: URL {
        statsURL.appendingPathComponent("stats.jsonl")
    }
    
    var stateURL: URL {
        rootURL.appendingPathComponent("state", isDirectory: true)
    }
    
    var runtimeStateURL: URL {
        stateURL.appendingPathComponent("runtime_state.json")
    }
    
    var iconsURL: URL {
        rootURL.appendingPathComponent("icons", isDirectory: true)
    }
    
    var baseDefaultsProfileURL: URL {
        profilesURL.appendingPathComponent("base_defaults.profile.json")
    }
    
    // MARK: - Initialization
    
    func ensureDirectoryStructure() {
        let fm = FileManager.default
        
        let directories = [
            rootURL,
            profilesURL,
            soundsURL,
            importedSoundsURL,
            statsURL,
            stateURL,
            iconsURL
        ]
        
        for dir in directories {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create directory \(dir): \(error)")
            }
        }
        
        // Create empty stats file if it doesn't exist
        if !fm.fileExists(atPath: statsFileURL.path) {
            fm.createFile(atPath: statsFileURL.path, contents: nil)
        }
    }
    
    // MARK: - URL Resolution
    
    /// Resolves custom URL schemes to file URLs
    /// - "bundle://Sounds/chime.mp3" -> Bundle resource URL
    /// - "apphome://sounds/imported/file.mp3" -> AppHome file URL
    func resolveURL(_ urlString: String) -> URL? {
        if urlString.hasPrefix("bundle://") {
            let path = String(urlString.dropFirst("bundle://".count))
            let components = path.split(separator: "/")
            guard components.count >= 2 else { return nil }
            let folder = String(components[0])
            let filename = components.dropFirst().joined(separator: "/")
            let nameWithoutExt = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            return Bundle.main.url(forResource: nameWithoutExt, withExtension: ext, subdirectory: folder)
        } else if urlString.hasPrefix("apphome://") {
            let path = String(urlString.dropFirst("apphome://".count))
            return rootURL.appendingPathComponent(path)
        } else {
            return URL(string: urlString) ?? URL(fileURLWithPath: urlString)
        }
    }
    
    // MARK: - Profile URLs
    
    func profileURL(for profileId: String) -> URL {
        profilesURL.appendingPathComponent("\(profileId).profile.json")
    }
    
    func listProfileFiles() -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: profilesURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents.filter { $0.pathExtension == "json" && $0.lastPathComponent.contains(".profile.") }
    }
    
    // MARK: - Actions
    
    func openInFinder() {
        NSWorkspace.shared.open(rootURL)
    }
    
    func generateImportedSoundFilename(originalName: String, format: String) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let safeName = originalName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "\(timestamp)_\(safeName).\(format)"
    }
    
    // MARK: - Icon Management
    
    /// Import a PNG icon file and return the filename
    func importIcon(from sourceURL: URL, named name: String) -> String? {
        let fm = FileManager.default
        
        // Validate format
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "png" else {
            print("Only PNG icons are supported")
            return nil
        }
        
        // Create safe filename
        let safeName = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .lowercased()
        let filename = "\(safeName).png"
        let destURL = iconsURL.appendingPathComponent(filename)
        
        // Remove existing file if present
        try? fm.removeItem(at: destURL)
        
        // Copy file
        do {
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            
            try fm.copyItem(at: sourceURL, to: destURL)
            return filename
        } catch {
            print("Failed to copy icon file: \(error)")
            return nil
        }
    }
    
    /// Get the URL for a custom icon filename
    func iconURL(for filename: String) -> URL {
        iconsURL.appendingPathComponent(filename)
    }
    
    /// List all imported icons
    func listImportedIcons() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: iconsURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { $0.lastPathComponent }
            .sorted()
    }
    
    /// Delete an imported icon
    func deleteIcon(filename: String) {
        let url = iconURL(for: filename)
        try? FileManager.default.removeItem(at: url)
    }
    
    /// Load an NSImage for a menu bar icon setting
    /// Value can be emoji like "🍅" or custom like "custom:filename.png"
    func loadMenuBarIcon(_ value: String, size: NSSize = NSSize(width: 18, height: 18)) -> NSImage? {
        if value.hasPrefix("custom:") {
            let filename = String(value.dropFirst("custom:".count))
            let url = iconURL(for: filename)
            guard let image = NSImage(contentsOf: url) else { return nil }
            image.size = size
            image.isTemplate = true  // Allows proper dark/light mode handling
            return image
        }
        return nil  // Return nil for emoji - will use text instead
    }
}
