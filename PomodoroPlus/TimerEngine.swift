import Foundation
import Combine
import AppKit

/// Core timer state machine managing work/break phases
@MainActor
class TimerEngine: ObservableObject {
    
    // MARK: - Published State
    
    @Published private(set) var phase: TimerPhase = .work
    @Published private(set) var state: TimerState = .idle
    @Published private(set) var remainingSeconds: TimeInterval = 0
    @Published private(set) var completedWorkSessions: Int = 0
    
    // Extra time (ignore break) state
    @Published private(set) var isInExtraTime: Bool = false
    @Published private(set) var extraTimeRemaining: TimeInterval = 0
    @Published private(set) var savedBreakRemaining: TimeInterval = 0
    
    // Post-break hold state
    @Published private(set) var isHoldingAfterBreak: Bool = false
    
    // MARK: - Callbacks
    
    var onBreakStart: (() -> Void)?
    var onBreakEnd: (() -> Void)?
    var onWarning: (() -> Void)?
    var onPhaseEnd: (() -> Void)?
    var onExtraTimeEnd: (() -> Void)?
    var onHoldAfterBreak: (() -> Void)?
    
    // MARK: - Private State
    
    private var phaseEndDate: Date?
    private var pausedRemaining: TimeInterval?
    private var phaseStartDate: Date?
    private var extraTimeEndDate: Date?
    
    /// Track if warning has been fired for the current phase to prevent duplicates
    private var warningFired = false
    
    /// Track the remaining time when warning was fired to detect if we've passed the warning threshold
    private var warningFiredAtRemaining: TimeInterval?
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Reduce UI churn/CPU by publishing countdown changes only when the displayed second changes.
    private var lastPublishedRemainingSecond: Int = Int.max
    private var lastPublishedExtraTimeSecond: Int = Int.max
    
    // MARK: - Dependencies
    
    private let profileStore: ProfileStore
    private let notificationScheduler: NotificationScheduler
    private let alarmPlayer: AlarmPlayer
    private let statsStore: StatsStore
    
    init(
        profileStore: ProfileStore,
        notificationScheduler: NotificationScheduler,
        alarmPlayer: AlarmPlayer,
        statsStore: StatsStore
    ) {
        self.profileStore = profileStore
        self.notificationScheduler = notificationScheduler
        self.alarmPlayer = alarmPlayer
        self.statsStore = statsStore
        
        setupObservers()
    }
    
    private func setupObservers() {
        // Listen for wake from sleep
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleWakeFromSleep()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Timer Control
    
    func start() {
        guard let profile = profileStore.currentProfile else { return }
        
        // If holding after break, start work session
        if isHoldingAfterBreak {
            isHoldingAfterBreak = false
            startWorkSession()
            return
        }
        
        if state == .paused, let remaining = pausedRemaining {
            // Resume from pause
            phaseEndDate = Date().addingTimeInterval(remaining)
            pausedRemaining = nil
            state = .running
            
            // Check if warning should have already fired based on remaining time
            let warningSecondsInt = phase.isBreak ? profile.notifications.breakWarningSecondsBeforeEnd : profile.notifications.workWarningSecondsBeforeEnd
            let warningSeconds = TimeInterval(warningSecondsInt)
            
            // Only reset warningFired if we haven't passed the warning threshold yet
            if remaining > warningSeconds {
                warningFired = false
                warningFiredAtRemaining = nil
            }
            // If remaining <= warningSeconds, keep warningFired as true to prevent duplicate
            
            scheduleNotifications()
            startTicking()
        } else if state == .idle {
            // Start fresh - begin new notification session
            notificationScheduler.startNewSession()
            
            phase = .work
            remainingSeconds = TimeInterval(profile.ruleset.workSeconds)
            phaseEndDate = Date().addingTimeInterval(remainingSeconds)
            phaseStartDate = Date()
            pausedRemaining = nil
            state = .running
            warningFired = false
            warningFiredAtRemaining = nil
            scheduleNotifications()
            startTicking()
        }
    }
    
    private func startWorkSession() {
        guard let profile = profileStore.currentProfile else { return }
        
        // Start new notification session for new phase
        notificationScheduler.startNewSession()
        
        phase = .work
        let duration = TimeInterval(profile.ruleset.workSeconds)
        remainingSeconds = duration
        phaseEndDate = Date().addingTimeInterval(duration)
        phaseStartDate = Date()
        pausedRemaining = nil
        state = .running
        warningFired = false
        warningFiredAtRemaining = nil
        
        onBreakEnd?()
        scheduleNotifications()
        startTicking()
    }
    
    func pause() {
        guard state == .running, let endDate = phaseEndDate else { return }
        
        pausedRemaining = endDate.timeIntervalSinceNow
        phaseEndDate = nil
        state = .paused
        
        stopTicking()
        cancelNotifications()
    }
    
    func resume() {
        start()
    }
    
    func toggleStartPause() {
        switch state {
        case .idle:
            start()
        case .running:
            pause()
        case .paused:
            resume()
        }
    }
    
    func reset() {
        stopTicking()
        cancelNotifications()
        alarmPlayer.stop()
        
        state = .idle
        phase = .work
        remainingSeconds = 0
        phaseEndDate = nil
        pausedRemaining = nil
        phaseStartDate = nil
        warningFired = false
        warningFiredAtRemaining = nil
        completedWorkSessions = 0
        isInExtraTime = false
        extraTimeRemaining = 0
        savedBreakRemaining = 0
        extraTimeEndDate = nil
        isHoldingAfterBreak = false
        
        // If we were on break, hide overlay
        onBreakEnd?()
    }
    
    func skip() {
        guard let profile = profileStore.currentProfile else { return }
        
        // If holding after break, just dismiss without starting work
        if isHoldingAfterBreak {
            isHoldingAfterBreak = false
            state = .idle
            onBreakEnd?()
            return
        }
        
        // Stop timer and cancel notifications immediately
        stopTicking()
        cancelNotifications()
        
        // Log stats for skipped phase
        if let startDate = phaseStartDate {
            let actualSeconds = Int(Date().timeIntervalSince(startDate))
            let plannedSeconds = plannedSecondsForPhase(phase, profile: profile)
            statsStore.log(
                profileId: profile.id,
                phase: phase,
                plannedSeconds: plannedSeconds,
                actualSeconds: actualSeconds,
                completed: false,
                skipped: true,
                strictMode: profile.overlay.strictDefault
            )
        }
        
        // Stop any playing alarm and move to next phase
        alarmPlayer.stop()
        advancePhase()
    }
    
    // MARK: - Extra Time (Ignore Break)
    
    func requestExtraTime() {
        guard let profile = profileStore.currentProfile,
              phase.isBreak,
              state == .running,
              !isInExtraTime else { return }
        
        // Save current break remaining time
        savedBreakRemaining = remainingSeconds
        
        // Stop break timer
        stopTicking()
        cancelNotifications()
        
        // Start extra time
        isInExtraTime = true
        let extraSeconds = TimeInterval(profile.overlay.extraTimeSeconds)
        extraTimeRemaining = extraSeconds
        extraTimeEndDate = Date().addingTimeInterval(extraSeconds)
        
        // Hide overlay during extra time
        onBreakEnd?()
        
        startTicking()
    }
    
    func endExtraTimeEarly() {
        guard isInExtraTime else { return }
        
        finishExtraTime()
    }
    
    private func finishExtraTime() {
        isInExtraTime = false
        extraTimeEndDate = nil
        extraTimeRemaining = 0
        
        // Resume break with saved time
        if savedBreakRemaining > 0 {
            remainingSeconds = savedBreakRemaining
            phaseEndDate = Date().addingTimeInterval(savedBreakRemaining)
            savedBreakRemaining = 0
            
            // Check if warning should fire for remaining break time
            if let profile = profileStore.currentProfile {
                let warningSecondsInt = phase.isBreak ? profile.notifications.breakWarningSecondsBeforeEnd : profile.notifications.workWarningSecondsBeforeEnd
                let warningSeconds = TimeInterval(warningSecondsInt)
                
                // Reset warning state only if we have enough time left
                if remainingSeconds > warningSeconds {
                    warningFired = false
                    warningFiredAtRemaining = nil
                } else {
                    // Already past warning threshold, mark as fired to prevent duplicate
                    warningFired = true
                    warningFiredAtRemaining = remainingSeconds
                }
            } else {
                warningFired = false
                warningFiredAtRemaining = nil
            }
            
            // Show overlay again
            onBreakStart?()
            
            // Start new notification session for resumed break
            notificationScheduler.startNewSession()
            scheduleNotifications()
        } else {
            // No break time left, advance to work
            advancePhase()
        }
        
        onExtraTimeEnd?()
    }
    
    // MARK: - Post-Break Hold
    
    func confirmStartWork() {
        guard isHoldingAfterBreak else { return }
        
        isHoldingAfterBreak = false
        startWorkSession()
    }
    
    func cancelAfterBreak() {
        guard isHoldingAfterBreak else { return }
        
        isHoldingAfterBreak = false
        state = .idle
        phase = .work
        remainingSeconds = 0
        onBreakEnd?()
    }
    
    // MARK: - Private Methods
    
    private func startTicking() {
        timer?.invalidate()
        // Use a non-scheduled timer and add it once to the common run loop modes.
        // (Avoids the same timer being registered in multiple modes via scheduledTimer + add.)
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    
    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }
    
    private func tick() {
        // Handle extra time tick
        if isInExtraTime {
            guard let endDate = extraTimeEndDate else { return }
            let newRemaining = max(0, endDate.timeIntervalSinceNow)
            let displaySecond = Int(ceil(newRemaining))
            if displaySecond != lastPublishedExtraTimeSecond || newRemaining <= 0 {
                extraTimeRemaining = newRemaining
                lastPublishedExtraTimeSecond = displaySecond
            }

            if newRemaining <= 0 {
                finishExtraTime()
            }
            return
        }
        
        guard state == .running, let endDate = phaseEndDate else { return }
        
        let newRemaining = max(0, endDate.timeIntervalSinceNow)
        let displaySecond = Int(ceil(newRemaining))
        if displaySecond != lastPublishedRemainingSecond || newRemaining <= 0 {
            remainingSeconds = newRemaining
            lastPublishedRemainingSecond = displaySecond
        }
        
        // Check for warning (tick-based backup - scheduled notification is primary)
        // Only fire if we haven't already fired a warning this phase
        if let profile = profileStore.currentProfile {
            let warningSecondsInt = phase.isBreak ? profile.notifications.breakWarningSecondsBeforeEnd : profile.notifications.workWarningSecondsBeforeEnd
            let warningSeconds = TimeInterval(warningSecondsInt)
            
            // Fire warning when we cross the threshold and haven't fired yet
            if newRemaining <= warningSeconds && !warningFired && newRemaining > 0 {
                warningFired = true
                warningFiredAtRemaining = newRemaining
                fireWarning()
            }
        }
        
        // Check for phase end
        if newRemaining <= 0 {
            phaseEnded()
        }
    }
    
    private func fireWarning() {
        guard let profile = profileStore.currentProfile else { return }
        
        onWarning?()
        
        // Play warning sound (work vs break) with volume and loop settings
        let soundId = phase.isBreak ? profile.sounds.breakWarningSoundId : profile.sounds.workWarningSoundId
        let volume = phase.isBreak ? profile.alarm.breakWarningVolume : profile.alarm.workWarningVolume
        
        if !soundId.isEmpty && soundId != "none" {
            let config: AlarmPlaybackConfig
            switch profile.alarm.loopMode {
            case .seconds:
                let duration = phase.isBreak ? profile.alarm.breakWarningPlaySeconds : profile.alarm.workWarningPlaySeconds
                config = AlarmPlaybackConfig(
                    maxDuration: TimeInterval(duration),
                    loopCount: 1,
                    loopMode: .seconds,
                    volume: volume
                )
            case .times:
                let loopCount = phase.isBreak ? profile.alarm.breakWarningLoopCount : profile.alarm.workWarningLoopCount
                config = AlarmPlaybackConfig(
                    maxDuration: 60, // Safety fallback
                    loopCount: loopCount,
                    loopMode: .times,
                    volume: volume
                )
            }
            alarmPlayer.play(soundId: soundId, config: config)
        }
    }
    
    private func phaseEnded() {
        guard let profile = profileStore.currentProfile else { return }
        
        stopTicking()
        cancelNotifications()
        
        onPhaseEnd?()
        
        // Log stats
        if let startDate = phaseStartDate {
            let actualSeconds = Int(Date().timeIntervalSince(startDate))
            let plannedSeconds = plannedSecondsForPhase(phase, profile: profile)
            statsStore.log(
                profileId: profile.id,
                phase: phase,
                plannedSeconds: plannedSeconds,
                actualSeconds: actualSeconds,
                completed: true,
                skipped: false,
                strictMode: profile.overlay.strictDefault
            )
        }
        
        // Play end sound with appropriate settings based on loop mode
        let soundId: String
        let volume: Double
        
        if phase == .work {
            // Work ended, break is starting
            soundId = profile.sounds.workEndSoundId
            volume = profile.alarm.workEndVolume
        } else {
            // Break ended
            soundId = profile.sounds.breakEndSoundId
            volume = profile.alarm.breakEndVolume
        }
        
        if !soundId.isEmpty && soundId != "none" {
            let config: AlarmPlaybackConfig
            switch profile.alarm.loopMode {
            case .seconds:
                let duration = (phase == .work) ? profile.alarm.breakStartPlaySeconds : profile.alarm.breakEndPlaySeconds
                config = AlarmPlaybackConfig(
                    maxDuration: TimeInterval(duration),
                    loopCount: 1,
                    loopMode: .seconds,
                    volume: volume
                )
            case .times:
                let loopCount = (phase == .work) ? profile.alarm.breakStartLoopCount : profile.alarm.breakEndLoopCount
                config = AlarmPlaybackConfig(
                    maxDuration: 120, // Safety fallback
                    loopCount: loopCount,
                    loopMode: .times,
                    volume: volume
                )
            }
            alarmPlayer.play(soundId: soundId, config: config)
        }
        
        // Track completed work sessions
        if phase == .work {
            completedWorkSessions += 1
        }
        
        // Check for post-break hold
        if phase.isBreak && profile.overlay.holdAfterBreak {
            isHoldingAfterBreak = true
            state = .idle
            remainingSeconds = 0
            onHoldAfterBreak?()
            return
        }
        
        // Advance phase
        advancePhase()
    }
    
    private func advancePhase() {
        guard let profile = profileStore.currentProfile else { return }
        
        let wasBreak = phase.isBreak
        
        // Determine next phase
        if phase == .work {
            if completedWorkSessions > 0 && completedWorkSessions % profile.ruleset.longBreakEvery == 0 {
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
        } else {
            phase = .work
        }
        
        // Start new notification session for new phase
        notificationScheduler.startNewSession()
        
        // Calculate duration
        let duration = TimeInterval(plannedSecondsForPhase(phase, profile: profile))
        remainingSeconds = duration
        warningFired = false
        warningFiredAtRemaining = nil
        
        // Handle break start/end callbacks
        if phase.isBreak && !wasBreak {
            onBreakStart?()
        } else if !phase.isBreak && wasBreak {
            onBreakEnd?()
        }
        
        // Auto-start based on settings
        if phase == .work && profile.features.autoStartWork {
            phaseEndDate = Date().addingTimeInterval(duration)
            phaseStartDate = Date()
            state = .running
            scheduleNotifications()
            startTicking()
        } else if phase.isBreak {
            // Always auto-start breaks
            phaseEndDate = Date().addingTimeInterval(duration)
            phaseStartDate = Date()
            state = .running
            scheduleNotifications()
            startTicking()
        } else {
            // Manual start required
            state = .idle
            phaseEndDate = nil
            phaseStartDate = nil
        }
    }
    
    private func plannedSecondsForPhase(_ phase: TimerPhase, profile: ProfileData) -> Int {
        switch phase {
        case .work: return profile.ruleset.workSeconds
        case .shortBreak: return profile.ruleset.shortBreakSeconds
        case .longBreak: return profile.ruleset.longBreakSeconds
        }
    }
    
    // MARK: - Notifications
    
    private func scheduleNotifications() {
        guard let profile = profileStore.currentProfile,
              let endDate = phaseEndDate,
              profile.notifications.bannerEnabled else { return }
        
        let warningSecondsInt = phase.isBreak ? profile.notifications.breakWarningSecondsBeforeEnd : profile.notifications.workWarningSecondsBeforeEnd
        let warningSeconds = TimeInterval(warningSecondsInt)
        let warningDate = endDate.addingTimeInterval(-warningSeconds)
        
        // Schedule warning notification only if warning hasn't already fired
        // and there's enough time left for the warning
        if warningDate > Date() && !warningFired {
            notificationScheduler.scheduleWarning(at: warningDate, phase: phase, warningSeconds: warningSecondsInt)
        }
        
        // Schedule end notification
        if endDate > Date() {
            notificationScheduler.schedulePhaseEnd(at: endDate, phase: phase)
        }
    }
    
    private func cancelNotifications() {
        notificationScheduler.cancelAll()
    }
    
    // MARK: - Sleep/Wake Handling
    
    private func handleWakeFromSleep() {
        // Handle extra time wake
        if isInExtraTime, let endDate = extraTimeEndDate {
            let remaining = endDate.timeIntervalSinceNow
            if remaining <= 0 {
                finishExtraTime()
            } else {
                extraTimeRemaining = remaining
                lastPublishedExtraTimeSecond = Int(ceil(remaining))
            }
            return
        }
        
        guard state == .running, let endDate = phaseEndDate else { return }
        
        let remaining = endDate.timeIntervalSinceNow
        
        if remaining <= 0 {
            // Phase ended while sleeping
            remainingSeconds = 0
            lastPublishedRemainingSecond = 0
            phaseEnded()
        } else {
            remainingSeconds = remaining
            lastPublishedRemainingSecond = Int(ceil(remaining))
            
            // Check if warning should have fired while sleeping
            if let profile = profileStore.currentProfile {
                let warningSecondsInt = phase.isBreak ? profile.notifications.breakWarningSecondsBeforeEnd : profile.notifications.workWarningSecondsBeforeEnd
                let warningSeconds = TimeInterval(warningSecondsInt)
                
                if remaining <= warningSeconds && !warningFired {
                    // Warning time passed while sleeping, fire it now
                    warningFired = true
                    warningFiredAtRemaining = remaining
                    fireWarning()
                }
            }
            
            // Reschedule notifications - start new session to avoid stale notifications
            notificationScheduler.startNewSession()
            scheduleNotifications()
        }
    }
    
    // MARK: - State Persistence
    
    func saveState() {
        // Save current state for potential restoration
        // Implementation optional for v1
    }
    
    func restoreState() {
        // Restore state from previous session
        // Implementation optional for v1
    }
    
    // MARK: - Display Helpers
    
    var formattedRemaining: String {
        let seconds = isInExtraTime ? extraTimeRemaining : remainingSeconds
        let display = max(0, Int(ceil(seconds)))
        let minutes = display / 60
        let secs = display % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    var formattedExtraTimeRemaining: String {
        let display = max(0, Int(ceil(extraTimeRemaining)))
        let minutes = display / 60
        let seconds = display % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
