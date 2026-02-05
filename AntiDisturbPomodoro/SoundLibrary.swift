import Foundation
import Combine

/// Manages the sound library, including built-in and imported sounds
class SoundLibrary: ObservableObject {
    
    @Published private(set) var sounds: [SoundEntry] = []
    
    private let appHome: AppHome
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(appHome: AppHome) {
        self.appHome = appHome
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    
    // MARK: - Load / Save
    
    func load() {
        let url = appHome.soundLibraryURL
        
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let library = try decoder.decode(SoundLibraryData.self, from: data)
                sounds = library.sounds
            } catch {
                print("Failed to load sound library: \(error)")
                createDefaultLibrary()
            }
        } else {
            createDefaultLibrary()
        }
    }
    
    func save() {
        let library = SoundLibraryData(version: 1, sounds: sounds)
        do {
            let data = try encoder.encode(library)
            try data.write(to: appHome.soundLibraryURL)
        } catch {
            print("Failed to save sound library: \(error)")
        }
    }
    
    // MARK: - Default Library
    
    private func createDefaultLibrary() {
        sounds = [
            SoundEntry(
                id: "builtin.chime",
                name: "Chime",
                format: "mp3",
                source: .builtIn,
                path: "bundle://Sounds/chime.mp3"
            ),
            SoundEntry(
                id: "builtin.bell",
                name: "Bell",
                format: "mp3",
                source: .builtIn,
                path: "bundle://Sounds/bell.mp3"
            ),
            SoundEntry(
                id: "builtin.gentle",
                name: "Gentle",
                format: "mp3",
                source: .builtIn,
                path: "bundle://Sounds/gentle.mp3"
            ),
            SoundEntry(
                id: "builtin.alert",
                name: "Alert",
                format: "mp3",
                source: .builtIn,
                path: "bundle://Sounds/alert.mp3"
            ),
            SoundEntry(
                id: "system.default",
                name: "System Default",
                format: "system",
                source: .builtIn,
                path: "system://default"
            )
        ]
        save()
    }
    
    // MARK: - Import
    
    func importSound(from sourceURL: URL) -> SoundEntry? {
        let fm = FileManager.default
        
        // Validate format
        let ext = sourceURL.pathExtension.lowercased()
        guard ["mp3", "m4a", "wav"].contains(ext) else {
            print("Unsupported audio format: \(ext)")
            return nil
        }
        
        // Generate unique filename
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let filename = appHome.generateImportedSoundFilename(originalName: originalName, format: ext)
        let destURL = appHome.importedSoundsURL.appendingPathComponent(filename)
        
        // Copy file
        do {
            // Start accessing security-scoped resource if needed
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            
            try fm.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("Failed to copy sound file: \(error)")
            return nil
        }
        
        // Create entry
        let id = "import.\(UUID().uuidString.prefix(8))"
        let entry = SoundEntry(
            id: id,
            name: originalName,
            format: ext,
            source: .imported,
            path: "apphome://sounds/imported/\(filename)"
        )
        
        sounds.append(entry)
        save()
        
        return entry
    }
    
    func importSounds(from urls: [URL]) -> [SoundEntry] {
        urls.compactMap { importSound(from: $0) }
    }
    
    // MARK: - Remove
    
    func removeSound(id: String) {
        guard let index = sounds.firstIndex(where: { $0.id == id }) else { return }
        let entry = sounds[index]
        
        // Only allow removing imported sounds
        guard entry.source == .imported else { return }
        
        // Delete file
        if let fileURL = appHome.resolveURL(entry.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        sounds.remove(at: index)
        save()
    }
    
    // MARK: - Lookup
    
    func sound(withId id: String) -> SoundEntry? {
        sounds.first { $0.id == id }
    }
    
    func resolveFileURL(for entry: SoundEntry) -> URL? {
        appHome.resolveURL(entry.path)
    }
    
    func resolveFileURL(forId id: String) -> URL? {
        guard let entry = sound(withId: id) else { return nil }
        return resolveFileURL(for: entry)
    }
    
    // MARK: - Helpers
    
    var builtInSounds: [SoundEntry] {
        sounds.filter { $0.source == .builtIn }
    }
    
    var importedSounds: [SoundEntry] {
        sounds.filter { $0.source == .imported }
    }
}
