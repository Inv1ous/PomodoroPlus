import Foundation
import AppKit
import SwiftUI
import Combine

/// Controls the menu bar status item and popover
@MainActor
class StatusBarController: NSObject {
    
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    private let appHome: AppHome
    private let soundLibrary: SoundLibrary
    private let profileStore: ProfileStore
    private let timerEngine: TimerEngine
    private let alarmPlayer: AlarmPlayer
    private let statsStore: StatsStore
    
    init(
        appHome: AppHome,
        soundLibrary: SoundLibrary,
        profileStore: ProfileStore,
        timerEngine: TimerEngine,
        alarmPlayer: AlarmPlayer,
        statsStore: StatsStore
    ) {
        self.appHome = appHome
        self.soundLibrary = soundLibrary
        self.profileStore = profileStore
        self.timerEngine = timerEngine
        self.alarmPlayer = alarmPlayer
        self.statsStore = statsStore
        
        super.init()
        
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        observeTimerUpdates()
    }

    deinit {
        // Note: deinit runs on arbitrary thread, so we need to be careful
        // The cancellables will be cleaned up automatically
        // Event monitor removal and status item removal should happen on main thread
        // but since this class is @MainActor, it should be fine
    }
    
    // MARK: - Cleanup (call before deallocation if needed)
    
    func cleanup() {
        if let eventMonitor = eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        cancellables.removeAll()
        
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
    
    // MARK: - Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "🍅"
            button.action = #selector(togglePopover)
            button.target = self
        }
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.behavior = .transient
        popover.animates = true
        
        let contentView = MenuBarPopoverView(
            appHome: appHome,
            soundLibrary: soundLibrary,
            profileStore: profileStore,
            timerEngine: timerEngine,
            alarmPlayer: alarmPlayer,
            statsStore: statsStore,
            closePopover: { [weak self] in self?.closePopover() }
        )
        
        popover.contentViewController = NSHostingController(rootView: contentView)
    }
    
    private func setupEventMonitor() {
        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.popover.isShown {
                    self.closePopover()
                }
            }
        }
    }
    
    private func observeTimerUpdates() {
        // Update menu bar when timer changes
        // Use Task to properly bridge Combine callbacks to MainActor context
        timerEngine.$remainingSeconds
            .combineLatest(timerEngine.$state, timerEngine.$phase, timerEngine.$isInExtraTime)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                Task { @MainActor in
                    self?.updateMenuBar()
                }
            }
            .store(in: &cancellables)
        
        profileStore.$currentProfileId
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateMenuBar()
                }
            }
            .store(in: &cancellables)
        
        // Also observe profile changes for icon updates
        profileStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateMenuBar()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateMenuBar() {
        guard let button = statusItem.button,
              let profile = profileStore.currentProfile else { return }
        
        let iconSettings = profile.features.menuBarIcons
        let showCountdown = profile.features.menuBarCountdownTextEnabled && (timerEngine.state != .idle || timerEngine.isInExtraTime)
        
        // Determine which icon to show based on state
        let iconValue: String
        if timerEngine.isInExtraTime {
            iconValue = "⏰"  // Special icon for extra time
        } else {
            switch timerEngine.state {
            case .idle:
                iconValue = iconSettings.idleIcon
            case .paused:
                iconValue = iconSettings.pausedIcon
            case .running:
                iconValue = timerEngine.phase.isBreak ? iconSettings.breakIcon : iconSettings.workIcon
            }
        }
        
        // Try to load custom image
        if iconSettings.useCustomIcons && !timerEngine.isInExtraTime,
           let image = appHome.loadMenuBarIcon(iconValue) {
            button.image = image
            button.imagePosition = showCountdown ? .imageLeft : .imageOnly
            button.title = showCountdown ? " \(timerEngine.formattedRemaining)" : ""
        } else {
            // Use emoji text
            button.image = nil
            if showCountdown {
                button.title = "\(iconValue) \(timerEngine.formattedRemaining)"
            } else {
                button.title = iconValue
            }
        }
    }
    
    // MARK: - Popover Actions
    
    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        
        // Activate app to ensure popover is interactive
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func closePopover() {
        popover.performClose(nil)
    }
}

// MARK: - Menu Bar Popover View

struct MenuBarPopoverView: View {
    @ObservedObject var appHome: AppHome
    @ObservedObject var soundLibrary: SoundLibrary
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var timerEngine: TimerEngine
    @ObservedObject var alarmPlayer: AlarmPlayer
    @ObservedObject var statsStore: StatsStore
    
    let closePopover: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with profile selector
            HStack {
                Text("Pomodoro")
                    .font(.headline)
                
                Spacer()
                
                Picker("", selection: $profileStore.currentProfileId) {
                    ForEach(profileStore.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .frame(width: 120)
                .labelsHidden()
            }
            
            Divider()
            
            // Timer Display
            VStack(spacing: 8) {
                if timerEngine.isInExtraTime {
                    Text("Extra Time")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                } else {
                    Text(timerEngine.phase.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(timerEngine.formattedRemaining)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Control Buttons
            HStack(spacing: 12) {
                if timerEngine.isInExtraTime {
                    // End Extra Time button
                    Button(action: { timerEngine.endExtraTimeEarly() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Resume Break")
                                .lineLimit(nil)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    // Start/Pause
                    Button(action: { timerEngine.toggleStartPause() }) {
                        Image(systemName: timerEngine.state == .running ? "pause.fill" : "play.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    // Reset
                    Button(action: { timerEngine.reset() }) {
                        Image(systemName: "stop.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(timerEngine.state == .idle)
                    
                    // Skip (if allowed)
                    if canSkip {
                        Button(action: { timerEngine.skip() }) {
                            Image(systemName: "forward.fill")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            
            // Stop Alarm button
            if alarmPlayer.isPlaying {
                Button("Stop Alarm") {
                    alarmPlayer.stop()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            
            Divider()
            
            // Quick Stats
            HStack {
                VStack(alignment: .leading) {
                    Text("Today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(statsStore.todaySummary.completedSessions) sessions")
                        .font(.subheadline)
                    Text("\(statsStore.todaySummary.totalFocusMinutes) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(timerEngine.completedWorkSessions)")
                        .font(.title2)
                }
            }
            
            Divider()
            
            // Footer Actions
            HStack {
                SettingsLink {
                    Text("Settings")
                }
                .buttonStyle(.link)
                
                Spacer()
                
                Button("Open Folder") {
                    appHome.openInFinder()
                }
                .buttonStyle(.link)
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
                .foregroundColor(.red)
            }
            .font(.caption)
        }
        .padding()
        .frame(width: 300)
    }
    
    private var statusText: String {
        if timerEngine.isInExtraTime {
            return "Break paused - finish up!"
        }
        switch timerEngine.state {
        case .idle: return "Ready to start"
        case .running: return "In progress"
        case .paused: return "Paused"
        }
    }
    
    private var canSkip: Bool {
        guard let profile = profileStore.currentProfile else { return false }
        guard timerEngine.state != .idle else { return false }
        
        // During work, always allow skip
        if timerEngine.phase == .work { return true }
        
        // During break, check strict mode
        return !profile.overlay.strictDefault
    }
}

