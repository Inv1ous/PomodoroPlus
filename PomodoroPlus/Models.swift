import Foundation

// MARK: - Sound Models

enum SoundIdCodec {
    private static let legacyIdMap: [String: String] = [
        "0": "builtin.chime",
        "1": "builtin.bell",
        "2": "builtin.gentle",
        "3": "builtin.alert",
        "4": "system.default",
        "chime": "builtin.chime",
        "bell": "builtin.bell",
        "gentle": "builtin.gentle",
        "alert": "builtin.alert",
        "default": "system.default",
        "system": "system.default",
        "system_default": "system.default",
        "builtin.default": "system.default"
    ]

    private static let builtInIds: Set<String> = [
        "builtin.chime",
        "builtin.bell",
        "builtin.gentle",
        "builtin.alert",
        "system.default"
    ]

    static func normalize(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "none" }

        let lowercased = trimmed.lowercased()

        if lowercased == "none" || lowercased == "off" || lowercased == "-1" {
            return "none"
        }
        if let mapped = legacyIdMap[lowercased] {
            return mapped
        }
        if lowercased.hasPrefix("builtin.") || lowercased == "system.default" {
            return lowercased
        }

        return trimmed
    }

    static func isBuiltInId(_ id: String) -> Bool {
        builtInIds.contains(normalize(id))
    }

    static func decodeOptionalStringId<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> String? {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return normalize(stringValue)
        }
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return normalize(String(intValue))
        }
        return nil
    }

    static func decodeStringId<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K,
        default defaultValue: String
    ) -> String {
        decodeOptionalStringId(from: container, forKey: key) ?? normalize(defaultValue)
    }
}

struct SoundLibraryData: Codable {
    var version: Int = 1
    var sounds: [SoundEntry]
}

struct SoundEntry: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var format: String
    var source: SoundSource
    var path: String
    
    enum SoundSource: String, Codable {
        case builtIn = "built_in"
        case imported = "imported"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case format
        case source
        case path
    }

    init(id: String, name: String, format: String, source: SoundSource, path: String) {
        self.id = SoundIdCodec.normalize(id)
        self.name = name
        self.format = format
        self.source = source
        self.path = path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedPath = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        let decodedSource = try container.decodeIfPresent(SoundSource.self, forKey: .source)
        let inferredImported = decodedPath.hasPrefix("apphome://sounds/imported/")

        id = SoundIdCodec.decodeOptionalStringId(from: container, forKey: .id)
            ?? (inferredImported ? "import.\(UUID().uuidString.prefix(8))" : "builtin.chime")
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Sound"
        format = (try container.decodeIfPresent(String.self, forKey: .format) ?? "mp3").lowercased()
        path = decodedPath

        if let decodedSource = decodedSource {
            source = decodedSource
        } else {
            source = inferredImported || id.hasPrefix("import.") ? .imported : .builtIn
        }

        if SoundIdCodec.isBuiltInId(id) {
            source = .builtIn
        }
    }
}

// MARK: - Profile Models

struct ProfileData: Codable, Identifiable {
    var version: Int = 1
    var id: String
    var name: String
    var ruleset: Ruleset
    var sounds: SoundSettings
    var notifications: NotificationSettings
    var alarm: AlarmSettings
    var overlay: OverlaySettings
    var features: FeatureSettings
    var hotkeys: HotkeySettings
    
    static func createDefault(id: String = "default", name: String = "Default") -> ProfileData {
        ProfileData(
            version: 1,
            id: id,
            name: name,
            ruleset: Ruleset(),
            sounds: SoundSettings(),
            notifications: NotificationSettings(),
            alarm: AlarmSettings(),
            overlay: OverlaySettings(),
            features: FeatureSettings(),
            hotkeys: HotkeySettings()
        )
    }
}

struct Ruleset: Codable, Equatable {
    var workSeconds: Int = 1500        // 25 minutes
    var shortBreakSeconds: Int = 300   // 5 minutes
    var longBreakSeconds: Int = 900    // 15 minutes
    var longBreakEvery: Int = 4        // Every 4 work sessions
}

struct SoundSettings: Codable, Equatable {
    var workEndSoundId: String = "builtin.chime"
    var breakEndSoundId: String = "builtin.chime"
    var workWarningSoundId: String = "builtin.chime"
    var breakWarningSoundId: String = "builtin.chime"

    init() {}

    init(workEndSoundId: String, breakEndSoundId: String, workWarningSoundId: String, breakWarningSoundId: String) {
        self.workEndSoundId = workEndSoundId
        self.breakEndSoundId = breakEndSoundId
        self.workWarningSoundId = workWarningSoundId
        self.breakWarningSoundId = breakWarningSoundId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // End sounds (new keys or defaults)
        workEndSoundId = SoundIdCodec.decodeStringId(from: container, forKey: .workEndSoundId, default: "builtin.chime")
        breakEndSoundId = SoundIdCodec.decodeStringId(from: container, forKey: .breakEndSoundId, default: "builtin.chime")

        // Warning sounds: prefer new keys, migrate from old single key if needed
        if let ww = SoundIdCodec.decodeOptionalStringId(from: container, forKey: .workWarningSoundId),
           let bw = SoundIdCodec.decodeOptionalStringId(from: container, forKey: .breakWarningSoundId) {
            workWarningSoundId = ww
            breakWarningSoundId = bw
        } else if let legacy = SoundIdCodec.decodeOptionalStringId(from: container, forKey: .warningSoundId) {
            workWarningSoundId = legacy
            breakWarningSoundId = legacy
        } else {
            workWarningSoundId = "builtin.chime"
            breakWarningSoundId = "builtin.chime"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case workEndSoundId
        case breakEndSoundId
        case workWarningSoundId
        case breakWarningSoundId
        case warningSoundId // legacy single warning sound id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(SoundIdCodec.normalize(workEndSoundId), forKey: .workEndSoundId)
        try container.encode(SoundIdCodec.normalize(breakEndSoundId), forKey: .breakEndSoundId)
        try container.encode(SoundIdCodec.normalize(workWarningSoundId), forKey: .workWarningSoundId)
        try container.encode(SoundIdCodec.normalize(breakWarningSoundId), forKey: .breakWarningSoundId)
    }
}

struct NotificationSettings: Codable, Equatable {
    var workWarningSecondsBeforeEnd: Int = 60
    var breakWarningSecondsBeforeEnd: Int = 60
    var bannerEnabled: Bool = true

    init() {}

    init(workWarningSecondsBeforeEnd: Int, breakWarningSecondsBeforeEnd: Int, bannerEnabled: Bool) {
        self.workWarningSecondsBeforeEnd = workWarningSecondsBeforeEnd
        self.breakWarningSecondsBeforeEnd = breakWarningSecondsBeforeEnd
        self.bannerEnabled = bannerEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Migrate from old single-value key if present
        if let oldWarning = try? container.decode(Int.self, forKey: .warningSecondsBeforeEnd) {
            workWarningSecondsBeforeEnd = oldWarning
            breakWarningSecondsBeforeEnd = oldWarning
            bannerEnabled = try container.decodeIfPresent(Bool.self, forKey: .bannerEnabled) ?? true
        } else {
            workWarningSecondsBeforeEnd = try container.decodeIfPresent(Int.self, forKey: .workWarningSecondsBeforeEnd) ?? 60
            breakWarningSecondsBeforeEnd = try container.decodeIfPresent(Int.self, forKey: .breakWarningSecondsBeforeEnd) ?? 60
            bannerEnabled = try container.decodeIfPresent(Bool.self, forKey: .bannerEnabled) ?? true
        }
    }

    private enum CodingKeys: String, CodingKey {
        case workWarningSecondsBeforeEnd
        case breakWarningSecondsBeforeEnd
        case bannerEnabled
        case warningSecondsBeforeEnd // Old key for migration
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workWarningSecondsBeforeEnd, forKey: .workWarningSecondsBeforeEnd)
        try container.encode(breakWarningSecondsBeforeEnd, forKey: .breakWarningSecondsBeforeEnd)
        try container.encode(bannerEnabled, forKey: .bannerEnabled)
    }
}

/// Determines whether alarm duration is measured in seconds or loop count
enum AlarmLoopMode: String, Codable, Equatable, CaseIterable {
    case seconds = "seconds"
    case times = "times"
    
    var displayName: String {
        switch self {
        case .seconds: return "seconds"
        case .times: return "times"
        }
    }
}

struct AlarmSettings: Codable, Equatable {
    var workWarningPlaySeconds: Int = 5
    var breakWarningPlaySeconds: Int = 5
    var breakStartPlaySeconds: Int = 10
    var breakEndPlaySeconds: Int = 10
    
    /// Loop mode: whether to use seconds or loop count
    var loopMode: AlarmLoopMode = .seconds
    
    /// Loop counts for each event (used when loopMode == .times)
    var workWarningLoopCount: Int = 2
    var breakWarningLoopCount: Int = 2
    var breakStartLoopCount: Int = 3
    var breakEndLoopCount: Int = 3
    
    /// Per-event volume scalars.
    ///
    /// UI range: 0.0 ... 2.0 (0% ... 200%).
    /// Values above 1.0 will boost the audio using gain amplification.
    var workEndVolume: Double = 1.0
    var breakEndVolume: Double = 1.0
    var workWarningVolume: Double = 1.0
    var breakWarningVolume: Double = 1.0
    
    init() {}
    
    init(
        workWarningPlaySeconds: Int,
        breakWarningPlaySeconds: Int,
        breakStartPlaySeconds: Int,
        breakEndPlaySeconds: Int,
        loopMode: AlarmLoopMode = .seconds,
        workWarningLoopCount: Int = 2,
        breakWarningLoopCount: Int = 2,
        breakStartLoopCount: Int = 3,
        breakEndLoopCount: Int = 3,
        workEndVolume: Double,
        breakEndVolume: Double,
        workWarningVolume: Double,
        breakWarningVolume: Double
    ) {
        self.workWarningPlaySeconds = workWarningPlaySeconds
        self.breakWarningPlaySeconds = breakWarningPlaySeconds
        self.breakStartPlaySeconds = breakStartPlaySeconds
        self.breakEndPlaySeconds = breakEndPlaySeconds
        self.loopMode = loopMode
        self.workWarningLoopCount = workWarningLoopCount
        self.breakWarningLoopCount = breakWarningLoopCount
        self.breakStartLoopCount = breakStartLoopCount
        self.breakEndLoopCount = breakEndLoopCount
        self.workEndVolume = workEndVolume
        self.breakEndVolume = breakEndVolume
        self.workWarningVolume = workWarningVolume
        self.breakWarningVolume = breakWarningVolume
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode loop mode (new field, defaults to .seconds for migration)
        loopMode = try container.decodeIfPresent(AlarmLoopMode.self, forKey: .loopMode) ?? .seconds
        
        // Decode loop counts (new fields, use defaults for migration)
        workWarningLoopCount = try container.decodeIfPresent(Int.self, forKey: .workWarningLoopCount) ?? 2
        breakWarningLoopCount = try container.decodeIfPresent(Int.self, forKey: .breakWarningLoopCount) ?? 2
        breakStartLoopCount = try container.decodeIfPresent(Int.self, forKey: .breakStartLoopCount) ?? 3
        breakEndLoopCount = try container.decodeIfPresent(Int.self, forKey: .breakEndLoopCount) ?? 3
        
        // Try new format first
        if let workWarning = try? container.decode(Int.self, forKey: .workWarningPlaySeconds) {
            workWarningPlaySeconds = workWarning
            breakWarningPlaySeconds = try container.decodeIfPresent(Int.self, forKey: .breakWarningPlaySeconds) ?? 5
            breakStartPlaySeconds = try container.decodeIfPresent(Int.self, forKey: .breakStartPlaySeconds) ?? 10
            breakEndPlaySeconds = try container.decodeIfPresent(Int.self, forKey: .breakEndPlaySeconds) ?? 10

            // Volume (new per-event keys) or migrate from legacy single `volume`
            let legacyVolume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
            workEndVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .workEndVolume) ?? legacyVolume)
            breakEndVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .breakEndVolume) ?? legacyVolume)
            workWarningVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .workWarningVolume) ?? legacyVolume)
            breakWarningVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .breakWarningVolume) ?? legacyVolume)
        }
        // Try old single warning format
        else if let oldWarning = try? container.decode(Int.self, forKey: .warningPlaySeconds) {
            workWarningPlaySeconds = oldWarning
            breakWarningPlaySeconds = oldWarning
            breakStartPlaySeconds = try container.decodeIfPresent(Int.self, forKey: .breakStartPlaySeconds) ?? 10
            breakEndPlaySeconds = try container.decodeIfPresent(Int.self, forKey: .breakEndPlaySeconds) ?? 10

            let legacyVolume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
            workEndVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .workEndVolume) ?? legacyVolume)
            breakEndVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .breakEndVolume) ?? legacyVolume)
            workWarningVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .workWarningVolume) ?? legacyVolume)
            breakWarningVolume = Self.clampVolume(try container.decodeIfPresent(Double.self, forKey: .breakWarningVolume) ?? legacyVolume)
        }
        // Fall back to old maxPlaySeconds format
        else if let maxPlay = try? container.decode(Int.self, forKey: .maxPlaySeconds) {
            workWarningPlaySeconds = min(maxPlay, 5)
            breakWarningPlaySeconds = min(maxPlay, 5)
            breakStartPlaySeconds = maxPlay
            breakEndPlaySeconds = maxPlay
            workEndVolume = 1.0
            breakEndVolume = 1.0
            workWarningVolume = 1.0
            breakWarningVolume = 1.0
        }
        // Use defaults
        else {
            workWarningPlaySeconds = 5
            breakWarningPlaySeconds = 5
            breakStartPlaySeconds = 10
            breakEndPlaySeconds = 10
            workEndVolume = 1.0
            breakEndVolume = 1.0
            workWarningVolume = 1.0
            breakWarningVolume = 1.0
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case workWarningPlaySeconds
        case breakWarningPlaySeconds
        case breakStartPlaySeconds
        case breakEndPlaySeconds
        case loopMode
        case workWarningLoopCount
        case breakWarningLoopCount
        case breakStartLoopCount
        case breakEndLoopCount
        case workEndVolume
        case breakEndVolume
        case workWarningVolume
        case breakWarningVolume
        case volume
        case warningPlaySeconds  // Old key for migration
        case maxPlaySeconds      // Oldest key for migration
    }

    private static func clampVolume(_ value: Double) -> Double {
        max(0.0, min(2.0, value))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workWarningPlaySeconds, forKey: .workWarningPlaySeconds)
        try container.encode(breakWarningPlaySeconds, forKey: .breakWarningPlaySeconds)
        try container.encode(breakStartPlaySeconds, forKey: .breakStartPlaySeconds)
        try container.encode(breakEndPlaySeconds, forKey: .breakEndPlaySeconds)
        
        try container.encode(loopMode, forKey: .loopMode)
        try container.encode(workWarningLoopCount, forKey: .workWarningLoopCount)
        try container.encode(breakWarningLoopCount, forKey: .breakWarningLoopCount)
        try container.encode(breakStartLoopCount, forKey: .breakStartLoopCount)
        try container.encode(breakEndLoopCount, forKey: .breakEndLoopCount)

        try container.encode(Self.clampVolume(workEndVolume), forKey: .workEndVolume)
        try container.encode(Self.clampVolume(breakEndVolume), forKey: .breakEndVolume)
        try container.encode(Self.clampVolume(workWarningVolume), forKey: .workWarningVolume)
        try container.encode(Self.clampVolume(breakWarningVolume), forKey: .breakWarningVolume)
    }
}

struct OverlaySettings: Codable, Equatable {
    var strictDefault: Bool = false
    var delayedSkipEnabled: Bool = false
    var delayedSkipSeconds: Int = 30
    
    // "Need More Time" feature
    var extraTimeEnabled: Bool = true
    var extraTimeSeconds: Int = 60  // Default 1 minute extra
    
    // Post-break behavior
    var holdAfterBreak: Bool = false  // Keep overlay at 0:00 after break ends
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strictDefault = try container.decodeIfPresent(Bool.self, forKey: .strictDefault) ?? true
        delayedSkipEnabled = try container.decodeIfPresent(Bool.self, forKey: .delayedSkipEnabled) ?? false
        delayedSkipSeconds = try container.decodeIfPresent(Int.self, forKey: .delayedSkipSeconds) ?? 30
        extraTimeEnabled = try container.decodeIfPresent(Bool.self, forKey: .extraTimeEnabled) ?? true
        extraTimeSeconds = try container.decodeIfPresent(Int.self, forKey: .extraTimeSeconds) ?? 60
        holdAfterBreak = try container.decodeIfPresent(Bool.self, forKey: .holdAfterBreak) ?? false
    }
    
    private enum CodingKeys: String, CodingKey {
        case strictDefault
        case delayedSkipEnabled
        case delayedSkipSeconds
        case extraTimeEnabled
        case extraTimeSeconds
        case holdAfterBreak
    }
}

struct FeatureSettings: Codable, Equatable {
    var autoStartWork: Bool = false
    var dailyStartEnabled: Bool = false
    var dailyStartTimeHHMM: String = "09:00"
    var menuBarCountdownTextEnabled: Bool = false
    var focusModeIntegrationEnabled: Bool = false
    var menuBarIcons: MenuBarIconSettings = MenuBarIconSettings()

    init() {}

    init(
        autoStartWork: Bool,
        dailyStartEnabled: Bool,
        dailyStartTimeHHMM: String,
        menuBarCountdownTextEnabled: Bool,
        focusModeIntegrationEnabled: Bool,
        menuBarIcons: MenuBarIconSettings
    ) {
        self.autoStartWork = autoStartWork
        self.dailyStartEnabled = dailyStartEnabled
        self.dailyStartTimeHHMM = dailyStartTimeHHMM
        self.menuBarCountdownTextEnabled = menuBarCountdownTextEnabled
        self.focusModeIntegrationEnabled = focusModeIntegrationEnabled
        self.menuBarIcons = menuBarIcons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoStartWork = try container.decodeIfPresent(Bool.self, forKey: .autoStartWork) ?? false
        dailyStartEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyStartEnabled) ?? false
        dailyStartTimeHHMM = try container.decodeIfPresent(String.self, forKey: .dailyStartTimeHHMM) ?? "09:00"
        menuBarCountdownTextEnabled = try container.decodeIfPresent(Bool.self, forKey: .menuBarCountdownTextEnabled) ?? false
        focusModeIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .focusModeIntegrationEnabled) ?? false
        menuBarIcons = try container.decodeIfPresent(MenuBarIconSettings.self, forKey: .menuBarIcons) ?? MenuBarIconSettings()
    }

    private enum CodingKeys: String, CodingKey {
        case autoStartWork
        case dailyStartEnabled
        case dailyStartTimeHHMM
        case menuBarCountdownTextEnabled
        case focusModeIntegrationEnabled
        case menuBarIcons
    }
}

struct MenuBarIconSettings: Codable, Equatable {
    var useCustomIcons: Bool = false
    // Values can be emoji like "🍅" or custom path like "custom:myicon.png"
    var idleIcon: String = "🍅"
    var workIcon: String = "🍅"
    var breakIcon: String = "☕️"
    var pausedIcon: String = "⏸️"
}

struct HotkeySettings: Codable, Equatable {
    var startPause: String = "cmd+shift+p"
    var stopAlarm: String = "cmd+shift+s"
    var skipPhase: String = "cmd+shift+k"
}

// MARK: - Stats Models

struct StatsEntry: Codable {
    var ts: String
    var profileId: String
    var phase: TimerPhase
    var plannedSeconds: Int
    var actualSeconds: Int
    var completed: Bool
    var skipped: Bool
    var strictMode: Bool
    
    static func create(
        profileId: String,
        phase: TimerPhase,
        plannedSeconds: Int,
        actualSeconds: Int,
        completed: Bool,
        skipped: Bool,
        strictMode: Bool
    ) -> StatsEntry {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return StatsEntry(
            ts: formatter.string(from: Date()),
            profileId: profileId,
            phase: phase,
            plannedSeconds: plannedSeconds,
            actualSeconds: actualSeconds,
            completed: completed,
            skipped: skipped,
            strictMode: strictMode
        )
    }
}

// MARK: - Timer Models

enum TimerPhase: String, Codable, Equatable {
    case work
    case shortBreak
    case longBreak
    
    var displayName: String {
        switch self {
        case .work: return "Work"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
    
    var isBreak: Bool {
        self == .shortBreak || self == .longBreak
    }
}

enum TimerState: Equatable {
    case idle
    case running
    case paused
}

struct RuntimeState: Codable {
    var profileId: String
    var phase: TimerPhase
    var phaseEndDate: Date?
    var pausedRemaining: TimeInterval?
    var completedWorkSessions: Int
    var isRunning: Bool
}

// MARK: - Stats Summary

struct StatsSummary {
    var totalSessions: Int = 0
    var completedSessions: Int = 0
    var totalFocusMinutes: Int = 0
    var skippedSessions: Int = 0
    
    static let empty = StatsSummary()
}
