import Foundation
import AppKit
import SwiftUI
import Combine

/// Manages full-screen overlay windows across all monitors during breaks
@MainActor
class OverlayManager: NSObject, ObservableObject {
    
    private var overlayWindows: [NSWindow] = []
    private var cancellables = Set<AnyCancellable>()
    
    private weak var timerEngine: TimerEngine?
    private weak var alarmPlayer: AlarmPlayer?
    private weak var profileStore: ProfileStore?
    
    @Published var skipEnabled = false
    @Published var skipCountdown: Int = 0
    @Published var isShowingPostBreakHold: Bool = false
    
    // Preserve delayed-skip state across extra time
    private var preservedSkipCountdown: Int?
    private var preservedSkipEnabled: Bool?
    
    private var skipTimer: Timer?
    
    init(timerEngine: TimerEngine, alarmPlayer: AlarmPlayer, profileStore: ProfileStore) {
        self.timerEngine = timerEngine
        self.alarmPlayer = alarmPlayer
        self.profileStore = profileStore
        super.init()
        
        // Observe hold after break
        timerEngine.$isHoldingAfterBreak
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isHolding in
                self?.isShowingPostBreakHold = isHolding
                if isHolding {
                    self?.refreshOverlayContent()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        cancellables.removeAll()
        Task { @MainActor [weak self] in
            self?.hideOverlay()
        }
    }
    
    // MARK: - Show/Hide Overlay
    
    func showOverlay() {
        // Close any existing overlays
        hideOverlay()
        
        guard let profile = profileStore?.currentProfile else { return }
        
        // Reset skip state
        skipEnabled = false
        skipCountdown = 0
        isShowingPostBreakHold = false
        
        // Create overlay for each screen
        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            overlayWindows.append(window)
            window.orderFrontRegardless()
        }
        
        // Handle delayed skip if enabled
        if profile.overlay.delayedSkipEnabled && !profile.overlay.strictDefault {
            if let preservedEnabled = preservedSkipEnabled {
                // Restore previously preserved state
                skipEnabled = preservedEnabled
                if !preservedEnabled {
                    let remaining = max(0, preservedSkipCountdown ?? profile.overlay.delayedSkipSeconds)
                    skipCountdown = remaining
                    startSkipCountdown()
                }
                // Clear preserved values after restoration
                preservedSkipEnabled = nil
                preservedSkipCountdown = nil
            } else {
                // Fresh countdown
                let delaySeconds = profile.overlay.delayedSkipSeconds
                skipCountdown = delaySeconds
                startSkipCountdown()
            }
        } else if !profile.overlay.strictDefault {
            // Not strict mode and no delay - enable skip immediately
            skipEnabled = true
        }
    }
    
    func hideOverlay() {
        skipTimer?.invalidate()
        skipTimer = nil
        
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        isShowingPostBreakHold = false
    }
    
    private func refreshOverlayContent() {
        // Recreate overlay windows to update content
        guard !overlayWindows.isEmpty else { return }
        
        let wasShowing = !overlayWindows.isEmpty
        hideOverlay()
        
        if wasShowing || isShowingPostBreakHold {
            for screen in NSScreen.screens {
                let window = createOverlayWindow(for: screen)
                overlayWindows.append(window)
                window.orderFrontRegardless()
            }
        }
    }
    
    // MARK: - Window Creation
    
    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        guard let timerEngine = timerEngine,
              let alarmPlayer = alarmPlayer,
              let profileStore = profileStore else {
            fatalError("Required dependencies not available")
        }
        
        let contentView = OverlayContentView(
            timerEngine: timerEngine,
            alarmPlayer: alarmPlayer,
            overlayManager: self,
            profileStore: profileStore
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        
        // Make the window full screen
        window.setFrame(screen.frame, display: true)
        
        return window
    }
    
    // MARK: - Skip Countdown
    
    private func startSkipCountdown() {
        skipTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.skipCountdown -= 1
                
                if self.skipCountdown <= 0 {
                    self.skipTimer?.invalidate()
                    self.skipTimer = nil
                    self.skipEnabled = true
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @MainActor func endBreak() {
        timerEngine?.skip()
    }
    
    func stopAlarm() {
        alarmPlayer?.stop()
    }
    
    @MainActor func requestExtraTime() {
        // Preserve delayed skip state so it can resume after extra time
        if let profile = profileStore?.currentProfile, profile.overlay.delayedSkipEnabled && !profile.overlay.strictDefault {
            preservedSkipEnabled = skipEnabled
            if !skipEnabled {
                preservedSkipCountdown = max(0, skipCountdown)
            } else {
                preservedSkipCountdown = nil
            }
        } else {
            preservedSkipEnabled = nil
            preservedSkipCountdown = nil
        }
        
        timerEngine?.requestExtraTime()
    }
    
    @MainActor func confirmStartWork() {
        timerEngine?.confirmStartWork()
    }
    
    @MainActor func cancelAfterBreak() {
        timerEngine?.cancelAfterBreak()
    }
}

// MARK: - SwiftUI Overlay Content

struct OverlayContentView: View {
    @ObservedObject var timerEngine: TimerEngine
    @ObservedObject var alarmPlayer: AlarmPlayer
    @ObservedObject var overlayManager: OverlayManager
    @ObservedObject var profileStore: ProfileStore
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            if timerEngine.isHoldingAfterBreak {
                postBreakHoldView
            } else {
                normalBreakView
            }
        }
    }
    
    // MARK: - Normal Break View
    
    private var normalBreakView: some View {
        VStack(spacing: 40) {
            // Phase indicator
            Text(timerEngine.phase.displayName)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
            
            // Timer display
            Text(timerEngine.formattedRemaining)
                .font(.system(size: 120, weight: .light, design: .monospaced))
                .foregroundColor(.white)
            
            // Progress message
            Text(breakMessage)
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
            
            // Buttons
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    // Stop Alarm button (always visible when playing)
                    if alarmPlayer.isPlaying {
                        Button(action: { overlayManager.stopAlarm() }) {
                            HStack {
                                Image(systemName: "speaker.slash.fill")
                                Text("Stop Alarm")
                            }
                            .font(.title3)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // End Break button (conditional)
                    if showEndBreakButton {
                        Button(action: { overlayManager.endBreak() }) {
                            HStack {
                                Image(systemName: "forward.fill")
                                Text(endBreakButtonText)
                            }
                            .font(.title3)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(buttonBackground)
                            .foregroundColor(buttonForeground)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(!overlayManager.skipEnabled)
                    }
                }
                
                // Extra Time button
                if showExtraTimeButton {
                    Button(action: { overlayManager.requestExtraTime() }) {
                        HStack {
                            ZStack(alignment: .bottomTrailing) {
                                Image(systemName: "clock")
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .offset(x: 4, y: 4)
                            }
                            .symbolRenderingMode(.hierarchical)
                            .imageScale(.large)
                            Text("I need \(extraTimeText)")
                        }
                        .font(.title3)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 20)
            
            // Skip countdown message
            if !overlayManager.skipEnabled && profileStore.currentProfile?.overlay.delayedSkipEnabled == true {
                Text("Skip available in \(overlayManager.skipCountdown)s")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    // MARK: - Post-Break Hold View
    
    private var postBreakHoldView: some View {
        VStack(spacing: 40) {
            // Completion message
            Text("Break Complete!")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
            
            // Timer shows 00:00
            Text("00:00")
                .font(.system(size: 120, weight: .light, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            
            Text("Ready to start your next work session?")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            // Buttons
            HStack(spacing: 20) {
                // Stop Alarm button (if playing)
                if alarmPlayer.isPlaying {
                    Button(action: { overlayManager.stopAlarm() }) {
                        HStack {
                            Image(systemName: "speaker.slash.fill")
                            Text("Stop Alarm")
                        }
                        .font(.title3)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                
                // Start Work button
                Button(action: { overlayManager.confirmStartWork() }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Work")
                    }
                    .font(.title3)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                // Cancel button
                Button(action: { overlayManager.cancelAfterBreak() }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .font(.title3)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)
        }
    }
    
    // MARK: - Computed Properties
    
    private var breakMessage: String {
        switch timerEngine.phase {
        case .shortBreak:
            return "Take a short break. Stretch, rest your eyes, grab some water."
        case .longBreak:
            return "Great work! Enjoy your well-deserved long break."
        case .work:
            return "Time to focus!"
        }
    }
    
    private var showEndBreakButton: Bool {
        guard let profile = profileStore.currentProfile else { return false }
        
        // Show if not strict, or if delayed skip is enabled
        return !profile.overlay.strictDefault || profile.overlay.delayedSkipEnabled
    }
    
    private var showExtraTimeButton: Bool {
        guard let profile = profileStore.currentProfile else { return false }
        return profile.overlay.extraTimeEnabled && !timerEngine.isInExtraTime
    }
    
    private var extraTimeText: String {
        guard let profile = profileStore.currentProfile else { return "1 min" }
        let seconds = profile.overlay.extraTimeSeconds
        let minsDecimal = Double(seconds) / 60.0
        // If it's an exact whole minute, keep integer minutes; otherwise show up to 2 decimal places
        if seconds % 60 == 0 {
            let whole = Int(minsDecimal)
            return "\(whole) min"
        } else {
            return String(format: "%.2f min", minsDecimal)
        }
    }
    
    private var endBreakButtonText: String {
        if overlayManager.skipEnabled {
            return "End Break"
        } else {
            return "End Break (\(overlayManager.skipCountdown)s)"
        }
    }
    
    private var buttonBackground: Color {
        overlayManager.skipEnabled ? Color.blue.opacity(0.8) : Color.gray.opacity(0.5)
    }
    
    private var buttonForeground: Color {
        overlayManager.skipEnabled ? .white : .white.opacity(0.5)
    }
}

