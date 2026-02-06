import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsView: View {
    
    var body: some View {
        TabView {
            ProfilesSettingsTab()
                .tabItem {
                    Label("Profiles", systemImage: "person.2")
                }
            
            TimingSettingsTab()
                .tabItem {
                    Label("Timing", systemImage: "clock")
                }
            
            SoundsSettingsTab()
                .tabItem {
                    Label("Sounds", systemImage: "speaker.wave.2")
                }
            
            OverlaySettingsTab()
                .tabItem {
                    Label("Break Overlay", systemImage: "rectangle.inset.filled")
                }
            
            FeaturesSettingsTab()
                .tabItem {
                    Label("Features", systemImage: "gearshape")
                }
            
            HotkeysSettingsTab()
                .tabItem {
                    Label("Hotkeys", systemImage: "command")
                }
            
            StatsSettingsTab()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
            
            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 580, height: 500)
        .overlay(SettingsWindowConfigurator().frame(width: 0, height: 0))
    }
}

// MARK: - Profiles Tab

struct ProfilesSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    
    @State private var newProfileName = ""
    @State private var showingNewProfile = false
    @State private var profileToDelete: ProfileData?
    @State private var showingDeleteConfirm = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Profile List
            VStack(alignment: .leading) {
                Text("Profiles")
                    .font(.headline)
                    .padding(.bottom, 8)
                
                List(profileStore.profiles, selection: $profileStore.currentProfileId) { profile in
                    HStack {
                        Text(profile.name)
                        if profile.id == profileStore.currentProfileId {
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .tag(profile.id)
                    .contextMenu {
                        Button("Duplicate") {
                            _ = profileStore.duplicateProfile(profile.id, newName: "\(profile.name) Copy")
                        }
                        Button("Delete", role: .destructive) {
                            profileToDelete = profile
                            showingDeleteConfirm = true
                        }
                        .disabled(profileStore.profiles.count <= 1)
                    }
                }
                .listStyle(.bordered)
                
                HStack {
                    Button(action: { showingNewProfile = true }) {
                        Image(systemName: "plus")
                    }
                    
                    Button(action: {
                        if let profile = profileStore.currentProfile {
                            profileToDelete = profile
                            showingDeleteConfirm = true
                        }
                    }) {
                        Image(systemName: "minus")
                    }
                    .disabled(profileStore.profiles.count <= 1)
                }
                .padding(.top, 4)
            }
            .frame(width: 180)
            .padding()
            
            Divider()
            
            // Profile Details
            VStack(alignment: .leading, spacing: 16) {
                if let profile = profileStore.currentProfile {
                    Text("Profile: \(profile.name)")
                        .font(.headline)
                    
                    HStack {
                        TextField("Name", text: Binding(
                            get: { profile.name },
                            set: { newValue in profileStore.renameProfile(profile.id, newName: newValue) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    }
                    
                    Spacer()
                    
                    Button("Reset to Defaults") {
                        profileStore.resetProfileToDefaults(profile.id)
                    }
                    .foregroundColor(.orange)
                    
                    Text("This will reset all settings for this profile to the base defaults.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Select a profile")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .alert("New Profile", isPresented: $showingNewProfile) {
            TextField("Profile name", text: $newProfileName)
            Button("Create") {
                if !newProfileName.isEmpty {
                    let newProfile = profileStore.createProfile(name: newProfileName)
                    profileStore.currentProfileId = newProfile.id
                    newProfileName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newProfileName = ""
            }
        }
        .alert("Delete Profile?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    profileStore.deleteProfile(profile.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(profileToDelete?.name ?? "")\"? This cannot be undone.")
        }
    }
}

// MARK: - Timing Tab

struct TimingSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Work Session") {
                    DurationPicker(
                        label: "Work Duration",
                        seconds: Binding(
                            get: { profile.ruleset.workSeconds },
                            set: { newValue in profileStore.updateCurrentProfile { $0.ruleset.workSeconds = newValue } }
                        ),
                        range: 1...7200  // 1 sec to 2 hours
                    )
                    
                    Stepper(
                        "Warning \(profile.notifications.workWarningSecondsBeforeEnd)s before end",
                        value: Binding(
                            get: { profile.notifications.workWarningSecondsBeforeEnd },
                            set: { newValue in profileStore.updateCurrentProfile { $0.notifications.workWarningSecondsBeforeEnd = newValue } }
                        ),
                        in: 10...300,
                        step: 5
                    )
                }
                
                Section("Short Break") {
                    DurationPicker(
                        label: "Short Break Duration",
                        seconds: Binding(
                            get: { profile.ruleset.shortBreakSeconds },
                            set: { newValue in profileStore.updateCurrentProfile { $0.ruleset.shortBreakSeconds = newValue } }
                        ),
                        range: 1...1800  // 1 sec to 30 min
                    )
                }
                
                Section("Long Break") {
                    DurationPicker(
                        label: "Long Break Duration",
                        seconds: Binding(
                            get: { profile.ruleset.longBreakSeconds },
                            set: { newValue in profileStore.updateCurrentProfile { $0.ruleset.longBreakSeconds = newValue } }
                        ),
                        range: 1...3600  // 1 sec to 1 hour
                    )
                    
                    Stepper(
                        "After every \(profile.ruleset.longBreakEvery) work sessions",
                        value: Binding(
                            get: { profile.ruleset.longBreakEvery },
                            set: { newValue in profileStore.updateCurrentProfile { $0.ruleset.longBreakEvery = newValue } }
                        ),
                        in: 2...10
                    )
                }
                
                Section("Break Warnings (Short & Long)") {
                    Stepper(
                        "Warning \(profile.notifications.breakWarningSecondsBeforeEnd)s before end",
                        value: Binding(
                            get: { profile.notifications.breakWarningSecondsBeforeEnd },
                            set: { newValue in profileStore.updateCurrentProfile { $0.notifications.breakWarningSecondsBeforeEnd = newValue } }
                        ),
                        in: 10...300,
                        step: 5
                    )
                    
                    Text("Applies to both short and long breaks.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("System Notifications") {
                    FeatureToggle(
                        title: "Show banner notifications",
                        isOn: Binding(
                            get: { profile.notifications.bannerEnabled },
                            set: { newValue in profileStore.updateCurrentProfile { $0.notifications.bannerEnabled = newValue } }
                        )
                    )
                }
            } else {
                Text("Select a profile to edit timing settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Sounds Tab

struct SoundsSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var soundLibrary: SoundLibrary
    @EnvironmentObject var alarmPlayer: AlarmPlayer
    
    @State private var showingImporter = false
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Sound Selection") {
                    SoundPickerRow(
                        title: "Work End",
                        soundId: Binding(
                            get: { profile.sounds.workEndSoundId },
                            set: { newValue in profileStore.updateCurrentProfile { $0.sounds.workEndSoundId = newValue } }
                        ),
                        volume: Binding(
                            get: { profile.alarm.workEndVolume },
                            set: { newValue in profileStore.updateCurrentProfile { $0.alarm.workEndVolume = newValue } }
                        )
                    )

                    SoundPickerRow(
                        title: "Break End",
                        soundId: Binding(
                            get: { profile.sounds.breakEndSoundId },
                            set: { newValue in profileStore.updateCurrentProfile { $0.sounds.breakEndSoundId = newValue } }
                        ),
                        volume: Binding(
                            get: { profile.alarm.breakEndVolume },
                            set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakEndVolume = newValue } }
                        )
                    )

                    SoundPickerRow(
                        title: "Work Warning",
                        soundId: Binding(
                            get: { profile.sounds.workWarningSoundId },
                            set: { newValue in profileStore.updateCurrentProfile { $0.sounds.workWarningSoundId = newValue } }
                        ),
                        volume: Binding(
                            get: { profile.alarm.workWarningVolume },
                            set: { newValue in profileStore.updateCurrentProfile { $0.alarm.workWarningVolume = newValue } }
                        )
                    )

                    SoundPickerRow(
                        title: "Break Warning",
                        soundId: Binding(
                            get: { profile.sounds.breakWarningSoundId },
                            set: { newValue in profileStore.updateCurrentProfile { $0.sounds.breakWarningSoundId = newValue } }
                        ),
                        volume: Binding(
                            get: { profile.alarm.breakWarningVolume },
                            set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakWarningVolume = newValue } }
                        )
                    )
                }
                
                Section("Alarm Duration") {
                    // Loop mode picker
                    Picker("Loop Mode", selection: Binding(
                        get: { profile.alarm.loopMode },
                        set: { newValue in profileStore.updateCurrentProfile { $0.alarm.loopMode = newValue } }
                    )) {
                        Text("Loop for X seconds").tag(AlarmLoopMode.seconds)
                        Text("Loop X times").tag(AlarmLoopMode.times)
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 8)
                    
                    if profile.alarm.loopMode == .seconds {
                        // Seconds-based settings
                        Stepper(
                            "Work warning: \(profile.alarm.workWarningPlaySeconds)s",
                            value: Binding(
                                get: { profile.alarm.workWarningPlaySeconds },
                                set: { newValue in profileStore.updateCurrentProfile { $0.alarm.workWarningPlaySeconds = newValue } }
                            ),
                            in: 1...60
                        )
                        
                        Stepper(
                            "Break warning: \(profile.alarm.breakWarningPlaySeconds)s",
                            value: Binding(
                                get: { profile.alarm.breakWarningPlaySeconds },
                                set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakWarningPlaySeconds = newValue } }
                            ),
                            in: 1...60
                        )
                        
                        Stepper(
                            "Work end (break starts): \(profile.alarm.breakStartPlaySeconds)s",
                            value: Binding(
                                get: { profile.alarm.breakStartPlaySeconds },
                                set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakStartPlaySeconds = newValue } }
                            ),
                            in: 1...120
                        )
                        
                        Stepper(
                            "Break end: \(profile.alarm.breakEndPlaySeconds)s",
                            value: Binding(
                                get: { profile.alarm.breakEndPlaySeconds },
                                set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakEndPlaySeconds = newValue } }
                            ),
                            in: 1...120
                        )
                    } else {
                        // Loop count settings
                        Stepper(
                            "Work warning: \(profile.alarm.workWarningLoopCount)x",
                            value: Binding(
                                get: { profile.alarm.workWarningLoopCount },
                                set: { newValue in profileStore.updateCurrentProfile { $0.alarm.workWarningLoopCount = newValue } }
                            ),
                            in: 1...20
                        )
                        
                        Stepper(
                            "Break warning: \(profile.alarm.breakWarningLoopCount)x",
                            value: Binding(
                                get: { profile.alarm.breakWarningLoopCount },
                                set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakWarningLoopCount = newValue } }
                            ),
                            in: 1...20
                        )
                        
                        Stepper(
                            "Work end (break starts): \(profile.alarm.breakStartLoopCount)x",
                            value: Binding(
                                get: { profile.alarm.breakStartLoopCount },
                                set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakStartLoopCount = newValue } }
                            ),
                            in: 1...20
                        )
                        
                        Stepper(
                            "Break end: \(profile.alarm.breakEndLoopCount)x",
                            value: Binding(
                                get: { profile.alarm.breakEndLoopCount },
                                set: { newValue in profileStore.updateCurrentProfile { $0.alarm.breakEndLoopCount = newValue } }
                            ),
                            in: 1...20
                        )
                    }
                    
                    Text(profile.alarm.loopMode == .seconds 
                         ? "Sound will loop continuously for the specified duration."
                         : "Sound will play the specified number of times.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Sound Library") {
                    VStack(alignment: .leading) {
                        Text("Built-in: \(soundLibrary.builtInSounds.count) • Imported: \(soundLibrary.importedSounds.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Import Sound File...") {
                        showingImporter = true
                    }
                    
                    if !soundLibrary.importedSounds.isEmpty {
                        ForEach(soundLibrary.importedSounds) { sound in
                            HStack {
                                Text(sound.name)
                                Text("(\(sound.format))")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Remove") {
                                    soundLibrary.removeSound(id: sound.id)
                                }
                                .buttonStyle(.link)
                                .foregroundColor(.red)
                            }
                        }
                    }
                }
            } else {
                Text("Select a profile to edit sound settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.mp3, .audio, UTType(filenameExtension: "m4a") ?? .audio, .wav],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                _ = soundLibrary.importSounds(from: urls)
            case .failure(let error):
                print("Import failed: \(error)")
            }
        }
    }
}

struct SoundPickerRow: View {
    let title: String
    @Binding var soundId: String
    @Binding var volume: Double
    
    @EnvironmentObject var soundLibrary: SoundLibrary
    @EnvironmentObject var alarmPlayer: AlarmPlayer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Picker("", selection: $soundId) {
                    Text("None").tag("none")
                    Divider()
                    ForEach(soundLibrary.sounds) { sound in
                        Text(sound.name).tag(sound.id)
                    }
                }
                .frame(width: 150)
                
                Button(action: {
                    if soundId != "none" {
                        alarmPlayer.testSound(soundId: soundId, maxDuration: 3, volume: volume)
                    }
                }) {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .disabled(soundId == "none")
            }
            
            VolumeControlRow(volume: $volume)
                .padding(.leading, 0)
        }
        .padding(.vertical, 4)
    }
}

fileprivate struct VolumeControlRow: View {
    @Binding var volume: Double
    
    private static let percentFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximum = 200
        return f
    }()
    
    private var percentBinding: Binding<Int> {
        Binding(
            get: { Int(round(Self.clamp(volume) * 100.0)) },
            set: { newPercent in
                let clamped = max(0, min(200, newPercent))
                volume = Double(clamped) / 100.0
            }
        )
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .imageScale(.medium)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)
                .help("Volume")
            
            TightSlider(value: $volume, range: 0...2)
                .frame(maxWidth: .infinity)

            
            HStack(spacing: 4) {
                TextField("", value: percentBinding, formatter: Self.percentFormatter)
                    .frame(width: 65, height: 24)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                Text("%")
                    .foregroundColor(.secondary)
            }
            .frame(width: 84, alignment: .trailing)
        }
    }
    
    private static func clamp(_ v: Double) -> Double {
        max(0.0, min(2.0, v))
    }
}

// MARK: - Overlay Tab

struct OverlaySettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Skip Break") {
                    FeatureToggle(
                        title: "Strict Mode (no skip button)",
                        isOn: Binding(
                            get: { profile.overlay.strictDefault },
                            set: { newValue in profileStore.updateCurrentProfile { $0.overlay.strictDefault = newValue } }
                        )
                    )
                    
                    Text("When enabled, you cannot skip breaks. This helps enforce rest periods.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !profile.overlay.strictDefault {
                        FeatureToggle(
                            title: "Delayed skip",
                            isOn: Binding(
                                get: { profile.overlay.delayedSkipEnabled },
                                set: { newValue in profileStore.updateCurrentProfile { $0.overlay.delayedSkipEnabled = newValue } }
                            )
                        )
                        
                        if profile.overlay.delayedSkipEnabled {
                            Stepper(
                                "Skip available after \(profile.overlay.delayedSkipSeconds)s",
                                value: Binding(
                                    get: { profile.overlay.delayedSkipSeconds },
                                    set: { newValue in profileStore.updateCurrentProfile { $0.overlay.delayedSkipSeconds = newValue } }
                                ),
                                in: 5...120,
                                step: 5
                            )
                        }
                    }
                }
                
                Section("Extra Time") {
                    FeatureToggle(
                        title: "Allow \"Need More Time\" button",
                        isOn: Binding(
                            get: { profile.overlay.extraTimeEnabled },
                            set: { newValue in profileStore.updateCurrentProfile { $0.overlay.extraTimeEnabled = newValue } }
                        )
                    )
                    
                    if profile.overlay.extraTimeEnabled {
                        Stepper(
                            "Extra time: \(formatDuration(profile.overlay.extraTimeSeconds))",
                            value: Binding(
                                get: { profile.overlay.extraTimeSeconds },
                                set: { newValue in profileStore.updateCurrentProfile { $0.overlay.extraTimeSeconds = newValue } }
                            ),
                            in: 15...300,
                            step: 15
                        )
                    }
                    
                    Text("Temporarily dismiss the overlay to finish something urgent. Break resumes after.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("After Break Ends") {
                    FeatureToggle(
                        title: "Hold overlay until manually dismissed",
                        isOn: Binding(
                            get: { profile.overlay.holdAfterBreak },
                            set: { newValue in profileStore.updateCurrentProfile { $0.overlay.holdAfterBreak = newValue } }
                        )
                    )
                    
                    Text("Keep the overlay at 0:00 and show Start/Cancel buttons instead of auto-advancing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Info") {
                    Text("The break overlay covers all connected monitors to help you take a proper break.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Select a profile to edit overlay settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        if seconds >= 60 {
            let mins = seconds / 60
            let secs = seconds % 60
            if secs > 0 {
                return "\(mins)m \(secs)s"
            }
            return "\(mins) min"
        }
        return "\(seconds)s"
    }
}

// MARK: - Features Tab

struct FeaturesSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var appHome: AppHome
    
    @State private var showingIconImporter = false
    @State private var importingForState: IconState = .idle
    
    enum IconState: String, CaseIterable {
        case idle = "Idle"
        case work = "Work"
        case breakTime = "Break"
        case paused = "Paused"
    }
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Auto-Start") {
                    FeatureToggle(
                        title: "Auto-start work after break",
                        isOn: Binding(
                            get: { profile.features.autoStartWork },
                            set: { newValue in profileStore.updateCurrentProfile { $0.features.autoStartWork = newValue } }
                        )
                    )
                    
                    Text("When enabled, work sessions start automatically after breaks end.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Menu Bar Display") {
                    FeatureToggle(
                        title: "Show countdown in menu bar",
                        isOn: Binding(
                            get: { profile.features.menuBarCountdownTextEnabled },
                            set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarCountdownTextEnabled = newValue } }
                        )
                    )
                    
                    FeatureToggle(
                        title: "Use custom PNG icons",
                        isOn: Binding(
                            get: { profile.features.menuBarIcons.useCustomIcons },
                            set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.useCustomIcons = newValue } }
                        )
                    )
                }
                
                if profile.features.menuBarIcons.useCustomIcons {
                    Section("Custom Icons (18x18 PNG recommended)") {
                        IconRow(
                            label: "Idle",
                            value: profile.features.menuBarIcons.idleIcon,
                            appHome: appHome,
                            onImport: { importingForState = .idle; showingIconImporter = true },
                            onClear: { profileStore.updateCurrentProfile { $0.features.menuBarIcons.idleIcon = "🍅" } }
                        )
                        
                        IconRow(
                            label: "Work",
                            value: profile.features.menuBarIcons.workIcon,
                            appHome: appHome,
                            onImport: { importingForState = .work; showingIconImporter = true },
                            onClear: { profileStore.updateCurrentProfile { $0.features.menuBarIcons.workIcon = "🍅" } }
                        )
                        
                        IconRow(
                            label: "Break",
                            value: profile.features.menuBarIcons.breakIcon,
                            appHome: appHome,
                            onImport: { importingForState = .breakTime; showingIconImporter = true },
                            onClear: { profileStore.updateCurrentProfile { $0.features.menuBarIcons.breakIcon = "☕️" } }
                        )
                        
                        IconRow(
                            label: "Paused",
                            value: profile.features.menuBarIcons.pausedIcon,
                            appHome: appHome,
                            onImport: { importingForState = .paused; showingIconImporter = true },
                            onClear: { profileStore.updateCurrentProfile { $0.features.menuBarIcons.pausedIcon = "⏸️" } }
                        )
                        
                        Text("Icons are set as template images for proper light/dark mode support.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Emoji Icons") {
                        EmojiIconRow(
                            label: "Idle",
                            value: Binding(
                                get: { profile.features.menuBarIcons.idleIcon },
                                set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.idleIcon = newValue } }
                            )
                        )
                        
                        EmojiIconRow(
                            label: "Work",
                            value: Binding(
                                get: { profile.features.menuBarIcons.workIcon },
                                set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.workIcon = newValue } }
                            )
                        )
                        
                        EmojiIconRow(
                            label: "Break",
                            value: Binding(
                                get: { profile.features.menuBarIcons.breakIcon },
                                set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.breakIcon = newValue } }
                            )
                        )
                        
                        EmojiIconRow(
                            label: "Paused",
                            value: Binding(
                                get: { profile.features.menuBarIcons.pausedIcon },
                                set: { newValue in profileStore.updateCurrentProfile { $0.features.menuBarIcons.pausedIcon = newValue } }
                            )
                        )
                    }
                }
                
                Section("Focus Mode") {
                    Text("Coming Soon")
                        .foregroundColor(.secondary)
                    
                    Text("macOS Focus Mode integration requires special entitlements.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Open Focus Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Focus")!)
                    }
                }
            } else {
                Text("Select a profile to edit feature settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(
            isPresented: $showingIconImporter,
            allowedContentTypes: [.png],
            allowsMultipleSelection: false
        ) { result in
            handleIconImport(result: result)
        }
    }
    
    private func handleIconImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            let filename = appHome.importIcon(from: url, named: importingForState.rawValue.lowercased())
            guard let filename = filename else { return }
            
            let customValue = "custom:\(filename)"
            
            profileStore.updateCurrentProfile { profile in
                switch importingForState {
                case .idle:
                    profile.features.menuBarIcons.idleIcon = customValue
                case .work:
                    profile.features.menuBarIcons.workIcon = customValue
                case .breakTime:
                    profile.features.menuBarIcons.breakIcon = customValue
                case .paused:
                    profile.features.menuBarIcons.pausedIcon = customValue
                }
            }
            
        case .failure(let error):
            print("Icon import failed: \(error)")
        }
    }
}

struct IconRow: View {
    let label: String
    let value: String
    let appHome: AppHome
    let onImport: () -> Void
    let onClear: () -> Void
    
    var body: some View {
        HStack {
            Text(label)
            
            Spacer()
            
            if value.hasPrefix("custom:") {
                if let image = appHome.loadMenuBarIcon(value, size: NSSize(width: 18, height: 18)) {
                    Image(nsImage: image)
                        .frame(width: 24, height: 24)
                }
                Text(String(value.dropFirst("custom:".count)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(value)
                    .font(.title3)
            }
            
            Button("Import") {
                onImport()
            }
            .buttonStyle(.bordered)
            
            Button("Clear") {
                onClear()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
        }
    }
}

struct EmojiIconRow: View {
    let label: String
    @Binding var value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $value)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Hotkeys Tab

struct HotkeysSettingsTab: View {
    @EnvironmentObject var profileStore: ProfileStore
    
    var body: some View {
        Form {
            if let profile = profileStore.currentProfile {
                Section("Global Hotkeys") {
                    HStack {
                        Text("Start/Pause Timer")
                        Spacer()
                        Text(profile.hotkeys.startPause)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("Stop Alarm")
                        Spacer()
                        Text(profile.hotkeys.stopAlarm)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("Skip Phase")
                        Spacer()
                        Text(profile.hotkeys.skipPhase)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Section {
                    Text("Hotkey customization will be available in a future update. The app requires Accessibility permissions for global hotkeys to work.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Open Accessibility Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            } else {
                Text("Select a profile to view hotkey settings.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Stats Tab

struct StatsSettingsTab: View {
    @EnvironmentObject var statsStore: StatsStore
    @EnvironmentObject var appHome: AppHome
    
    var body: some View {
        Form {
            Section("Today") {
                StatRow(label: "Completed Sessions", value: "\(statsStore.todaySummary.completedSessions)")
                StatRow(label: "Total Focus Time", value: "\(statsStore.todaySummary.totalFocusMinutes) minutes")
                StatRow(label: "Skipped", value: "\(statsStore.todaySummary.skippedSessions)")
            }
            
            Section("This Week") {
                StatRow(label: "Completed Sessions", value: "\(statsStore.weekSummary.completedSessions)")
                StatRow(label: "Total Focus Time", value: "\(statsStore.weekSummary.totalFocusMinutes) minutes")
                StatRow(label: "Skipped", value: "\(statsStore.weekSummary.skippedSessions)")
            }
            
            Section("All Time") {
                StatRow(label: "Completed Sessions", value: "\(statsStore.allTimeSummary.completedSessions)")
                StatRow(label: "Total Focus Time", value: formatHours(statsStore.allTimeSummary.totalFocusMinutes))
                StatRow(label: "Skipped", value: "\(statsStore.allTimeSummary.skippedSessions)")
            }
            
            Section {
                Button("Open Stats File") {
                    NSWorkspace.shared.activateFileViewerSelecting([appHome.statsFileURL])
                }
                
                Text("Stats are stored in stats.jsonl in the app folder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func formatHours(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes) minutes"
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Reusable Components

/// Consistent feature toggle with highlighted background when enabled
struct FeatureToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack {
                Text(title)
                Spacer()
            }
        }
        // Force the switch to use our intended active/tint styling.
        // (Menu bar apps can sometimes present settings while the window is not yet key,
        // which can make switches appear "inactive grey" until reopened.)
        .toggleStyle(.switch)
        .tint(.orange)
        .environment(\.controlActiveState, .active)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(isOn ? Color.orange.opacity(0.15) : Color.clear)
        .cornerRadius(6)
    }
}

/// Duration picker with minutes and seconds
struct DurationPicker: View {
    let label: String
    @Binding var seconds: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(alignment: .center, spacing: 6) {
                TextField("", value: Binding(
                    get: { seconds / 60 },
                    set: { newMins in 
                        let currentSecs = seconds % 60
                        let newTotal = newMins * 60 + currentSecs
                        seconds = max(range.lowerBound, min(range.upperBound, newTotal))
                    }
                ), formatter: NumberFormatter())
                .frame(width: 60, height: 24)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                
                Text("m")
                    .foregroundColor(.secondary)
                    .frame(width: 12, height: 24, alignment: .center)
                
                TextField("", value: Binding(
                    get: { seconds % 60 },
                    set: { newSecs in
                        let currentMins = seconds / 60
                        let newTotal = currentMins * 60 + newSecs
                        seconds = max(range.lowerBound, min(range.upperBound, newTotal))
                    }
                ), formatter: NumberFormatter())
                .frame(width: 60, height: 24)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                
                Text("s")
                    .foregroundColor(.secondary)
                    .frame(width: 12, height: 24, alignment: .center)
            }
            
            Stepper("", value: $seconds, in: range, step: 1)
                .labelsHidden()
        }
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    @EnvironmentObject var updateChecker: UpdateChecker
    
    var body: some View {
        Form {
            Section("Application") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(UpdateChecker.currentVersion)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text(UpdateChecker.currentBuild)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Updates") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Check for Updates")
                        if updateChecker.updateAvailable, let version = updateChecker.latestVersion {
                            Text("Version \(version) is available!")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if let error = updateChecker.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Spacer()
                    
                    if updateChecker.isChecking {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if updateChecker.isDownloading {
                        VStack(alignment: .trailing, spacing: 4) {
                            ProgressView(value: updateChecker.downloadProgress)
                                .frame(width: 100)
                            Text("\(Int(updateChecker.downloadProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Button("Cancel") {
                            updateChecker.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Check Now") {
                            updateChecker.checkForUpdates(silent: false)
                        }
                        .buttonStyle(.bordered)
                        
                        if updateChecker.updateAvailable {
                            Button("Download & Install") {
                                updateChecker.downloadAndInstall()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                
                Text("Updates are automatically checked on app startup.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Troubleshooting")
                    Spacer()
                    Button("View Update Log") {
                        updateChecker.openUpdateLog()
                    }
                    .buttonStyle(.link)
                }
            }
            
            Section("Support") {
                HStack {
                    Text("Report Issues")
                    Spacer()
                    Button("Open GitHub Issues") {
                        if let url = URL(string: "https://github.com/\(UpdateChecker.repoOwner)/\(UpdateChecker.repoName)/issues") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
                
                HStack {
                    Text("Source Code")
                    Spacer()
                    Button("View on GitHub") {
                        if let url = URL(string: "https://github.com/\(UpdateChecker.repoOwner)/\(UpdateChecker.repoName)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
            }
            
            Section("Credits") {
                Text("AntiDisturb Pomodoro")
                    .font(.headline)
                Text("A focus timer that respects your work.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

// Preview disabled - requires complex environment object setup
// To preview, run the app and open Settings

