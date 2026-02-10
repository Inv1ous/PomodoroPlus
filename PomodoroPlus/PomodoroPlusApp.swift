import SwiftUI
import AppKit

@main
struct PomodoroPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appHome)
                .environmentObject(appDelegate.soundLibrary)
                .environmentObject(appDelegate.profileStore)
                .environmentObject(appDelegate.timerEngine)
                .environmentObject(appDelegate.alarmPlayer)
                .environmentObject(appDelegate.statsStore)
                .environmentObject(appDelegate.updateChecker)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    
    let appHome = AppHome()
    lazy var soundLibrary = SoundLibrary(appHome: appHome)
    lazy var profileStore = ProfileStore(appHome: appHome)
    lazy var statsStore = StatsStore(appHome: appHome)
    lazy var alarmPlayer = AlarmPlayer(soundLibrary: soundLibrary)
    lazy var notificationScheduler = NotificationScheduler()
    lazy var updateChecker = UpdateChecker()
    lazy var timerEngine: TimerEngine = {
        let engine = TimerEngine(
            profileStore: profileStore,
            notificationScheduler: notificationScheduler,
            alarmPlayer: alarmPlayer,
            statsStore: statsStore
        )
        return engine
    }()
    lazy var overlayManager = OverlayManager(timerEngine: timerEngine, alarmPlayer: alarmPlayer, profileStore: profileStore)
    lazy var hotkeyManager = HotkeyManager(timerEngine: timerEngine, alarmPlayer: alarmPlayer)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize app home directory
        appHome.ensureDirectoryStructure()
        
        // Load data
        soundLibrary.load()
        profileStore.load()
        statsStore.load()
        
        // Request notification permissions
        notificationScheduler.requestPermission()
        
        // Setup timer engine callbacks
        setupTimerEngineCallbacks()
        
        // Create status bar
        statusBarController = StatusBarController(
            appHome: appHome,
            soundLibrary: soundLibrary,
            profileStore: profileStore,
            timerEngine: timerEngine,
            alarmPlayer: alarmPlayer,
            statsStore: statsStore
        )
        
        // Register hotkeys
        hotkeyManager.registerHotkeys()
        
        // Hide dock icon (menu bar app)
        NSApp.setActivationPolicy(.accessory)
        
        // Check for updates on startup (after a short delay to let the app fully launch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.updateChecker.checkOnStartup()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        timerEngine.saveState()
        hotkeyManager.unregisterHotkeys()
    }
    
    private func setupTimerEngineCallbacks() {
        timerEngine.onBreakStart = { [weak self] in
            DispatchQueue.main.async {
                self?.overlayManager.showOverlay()
            }
        }
        
        timerEngine.onBreakEnd = { [weak self] in
            DispatchQueue.main.async {
                self?.overlayManager.hideOverlay()
            }
        }
        
        timerEngine.onExtraTimeEnd = {
            // Extra time ended. Do not show overlay here because onBreakStart will handle it.
            // Calling showOverlay here would cause a second show that resets delayed-skip state.
        }
        
        timerEngine.onHoldAfterBreak = { [weak self] in
            // Keep overlay showing with post-break UI
            DispatchQueue.main.async {
                self?.overlayManager.showOverlay()
            }
        }
    }
}
