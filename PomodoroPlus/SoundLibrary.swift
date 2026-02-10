import Foundation
import Combine

/// Manages the sound library, including built-in and imported sounds
class SoundLibrary: ObservableObject {
    
    @Published private(set) var sounds: [SoundEntry] = []
    
    private let appHome: AppHome
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let supportedAudioFormats: Set<String> = ["mp3", "m4a", "wav"]
    private static let canonicalBuiltInSounds: [SoundEntry] = [
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
                let reconciled = reconcileSounds(library.sounds)
                sounds = reconciled
                if reconciled != library.sounds {
                    save()
                }
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
        sounds = Self.canonicalBuiltInSounds
        save()
    }

    private func reconcileSounds(_ loadedSounds: [SoundEntry]) -> [SoundEntry] {
        var importedSounds: [SoundEntry] = []
        var usedImportedIds = Set<String>()

        for var entry in loadedSounds {
            entry.id = SoundIdCodec.normalize(entry.id)

            let isImported =
                entry.source == .imported ||
                entry.id.hasPrefix("import.") ||
                entry.path.hasPrefix("apphome://sounds/imported/")
            guard isImported else { continue }

            entry.source = .imported

            if entry.id.isEmpty || entry.id == "none" || SoundIdCodec.isBuiltInId(entry.id) {
                entry.id = Self.makeUniqueImportedId(existingIds: &usedImportedIds)
            } else if usedImportedIds.contains(entry.id) {
                entry.id = Self.makeUniqueImportedId(existingIds: &usedImportedIds)
            } else {
                usedImportedIds.insert(entry.id)
            }

            importedSounds.append(entry)
        }

        return Self.canonicalBuiltInSounds + importedSounds
    }

    private static func makeUniqueImportedId(existingIds: inout Set<String>) -> String {
        var candidate: String
        repeat {
            candidate = "import.\(UUID().uuidString.prefix(8))"
        } while existingIds.contains(candidate)
        existingIds.insert(candidate)
        return candidate
    }
    
    // MARK: - Import
    
    func importSound(from sourceURL: URL) -> SoundEntry? {
        let fm = FileManager.default
        
        // Validate format
        let ext = sourceURL.pathExtension.lowercased()
        guard Self.supportedAudioFormats.contains(ext) else {
            print("Unsupported audio format: \(ext)")
            return nil
        }
        
        // Generate unique filename
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let destURL = nextAvailableImportDestinationURL(originalName: originalName, format: ext)
        
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
        var usedIds = Set(sounds.map(\.id))
        let id = Self.makeUniqueImportedId(existingIds: &usedIds)
        let entry = SoundEntry(
            id: id,
            name: originalName,
            format: ext,
            source: .imported,
            path: "apphome://sounds/imported/\(destURL.lastPathComponent)"
        )
        
        sounds.append(entry)
        save()
        
        return entry
    }

    private func nextAvailableImportDestinationURL(originalName: String, format: String) -> URL {
        let fm = FileManager.default
        let initialFilename = appHome.generateImportedSoundFilename(originalName: originalName, format: format)
        let baseName = (initialFilename as NSString).deletingPathExtension

        var candidateFilename = initialFilename
        var candidateURL = appHome.importedSoundsURL.appendingPathComponent(candidateFilename)
        var attempt = 1

        while fm.fileExists(atPath: candidateURL.path) {
            candidateFilename = "\(baseName)_\(attempt).\(format)"
            candidateURL = appHome.importedSoundsURL.appendingPathComponent(candidateFilename)
            attempt += 1
        }

        return candidateURL
    }
    
    func importSounds(from urls: [URL]) -> [SoundEntry] {
        urls.compactMap { importSound(from: $0) }
    }
    
    // MARK: - Remove
    
    func removeSound(id: String) {
        let normalizedId = SoundIdCodec.normalize(id)
        guard let index = sounds.firstIndex(where: { $0.id == normalizedId }) else { return }
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
        let normalizedId = SoundIdCodec.normalize(id)
        return sounds.first { $0.id == normalizedId }
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
