import Foundation
import Combine

/// Manages user profiles including CRUD operations and resetting to defaults
class ProfileStore: ObservableObject {
    
    @Published private(set) var profiles: [ProfileData] = []
    @Published var currentProfileId: String = "default"
    
    private let appHome: AppHome
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(appHome: AppHome) {
        self.appHome = appHome
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    
    // MARK: - Current Profile
    
    var currentProfile: ProfileData? {
        get { profiles.first { $0.id == currentProfileId } }
        set {
            if let newValue = newValue, let index = profiles.firstIndex(where: { $0.id == newValue.id }) {
                profiles[index] = newValue
                saveProfile(newValue)
                profiles = profiles
            }
        }
    }
    
    // MARK: - Load / Save
    
    func load() {
        ensureBaseDefaults()
        loadAllProfiles()
        
        // Ensure at least one profile exists
        if profiles.isEmpty {
            let defaultProfile = ProfileData.createDefault()
            profiles.append(defaultProfile)
            saveProfile(defaultProfile)
        }
        
        // Ensure current profile ID is valid
        if !profiles.contains(where: { $0.id == currentProfileId }) {
            currentProfileId = profiles.first?.id ?? "default"
        }
    }
    
    private func ensureBaseDefaults() {
        let url = appHome.baseDefaultsProfileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let baseDefaults = ProfileData.createDefault(id: "base_defaults", name: "Base Defaults")
            do {
                let data = try encoder.encode(baseDefaults)
                try data.write(to: url)
            } catch {
                print("Failed to create base defaults: \(error)")
            }
        }
    }
    
    private func loadAllProfiles() {
        profiles = []
        let profileFiles = appHome.listProfileFiles()
        
        for url in profileFiles {
            // Skip base_defaults
            if url.lastPathComponent == "base_defaults.profile.json" { continue }
            
            do {
                let data = try Data(contentsOf: url)
                let profile = try decoder.decode(ProfileData.self, from: data)
                profiles.append(profile)
            } catch {
                print("Failed to load profile \(url): \(error)")
            }
        }
        
        // Sort by name
        profiles.sort { $0.name < $1.name }
    }
    
    func saveProfile(_ profile: ProfileData) {
        let url = appHome.profileURL(for: profile.id)
        do {
            let data = try encoder.encode(profile)
            try data.write(to: url)
        } catch {
            print("Failed to save profile \(profile.id): \(error)")
        }
    }
    
    // MARK: - CRUD Operations
    
    func createProfile(name: String) -> ProfileData {
        let id = "profile_\(UUID().uuidString.prefix(8))"
        var profile = ProfileData.createDefault(id: id, name: name)
        
        // Copy settings from base defaults
        if let baseDefaults = loadBaseDefaults() {
            profile.ruleset = baseDefaults.ruleset
            profile.sounds = baseDefaults.sounds
            profile.notifications = baseDefaults.notifications
            profile.alarm = baseDefaults.alarm
            profile.overlay = baseDefaults.overlay
            profile.features = baseDefaults.features
            profile.hotkeys = baseDefaults.hotkeys
        }
        
        profiles.append(profile)
        profiles.sort { $0.name < $1.name }
        saveProfile(profile)
        
        return profile
    }
    
    func duplicateProfile(_ profileId: String, newName: String) -> ProfileData? {
        guard let original = profiles.first(where: { $0.id == profileId }) else { return nil }
        
        let id = "profile_\(UUID().uuidString.prefix(8))"
        var copy = original
        copy.id = id
        copy.name = newName
        
        profiles.append(copy)
        profiles.sort { $0.name < $1.name }
        saveProfile(copy)
        
        return copy
    }
    
    func deleteProfile(_ profileId: String) {
        // Don't delete if it's the only profile
        guard profiles.count > 1 else { return }
        
        // Remove from memory
        profiles.removeAll { $0.id == profileId }
        
        // Delete file
        let url = appHome.profileURL(for: profileId)
        try? FileManager.default.removeItem(at: url)
        
        // Switch to another profile if current was deleted
        if currentProfileId == profileId {
            currentProfileId = profiles.first?.id ?? "default"
        }
    }
    
    func renameProfile(_ profileId: String, newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
        profiles[index].name = newName
        profiles.sort { $0.name < $1.name }
        saveProfile(profiles.first { $0.id == profileId }!)
    }
    
    // MARK: - Reset to Defaults
    
    func resetProfileToDefaults(_ profileId: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileId }),
              let baseDefaults = loadBaseDefaults() else { return }
        
        let originalName = profiles[index].name
        let originalId = profiles[index].id
        
        // Keep name and ID, reset everything else
        var resetProfile = baseDefaults
        resetProfile.id = originalId
        resetProfile.name = originalName
        
        profiles[index] = resetProfile
        saveProfile(resetProfile)
        DispatchQueue.main.async {
            self.profiles = self.profiles
        }
    }
    
    private func loadBaseDefaults() -> ProfileData? {
        let url = appHome.baseDefaultsProfileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(ProfileData.self, from: data)
        } catch {
            print("Failed to load base defaults: \(error)")
            return nil
        }
    }
    
    // MARK: - Update Current Profile
    
    func updateCurrentProfile(_ update: (inout ProfileData) -> Void) {
        guard var profile = currentProfile else { return }
        update(&profile)
        DispatchQueue.main.async {
            self.currentProfile = profile
        }
    }
}
