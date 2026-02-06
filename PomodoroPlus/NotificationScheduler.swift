import Foundation
import UserNotifications

/// Schedules and manages system banner notifications
class NotificationScheduler: NSObject, ObservableObject {
    
    @Published private(set) var hasPermission = false
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    /// Unique session ID to prevent stale notifications from previous timer sessions
    private var currentSessionId: UUID = UUID()
    
    /// Track all pending notification identifiers for the current session
    private var pendingIdentifiers: Set<String> = []
    
    /// Track session IDs that have been invalidated (to catch late-delivered notifications)
    private var invalidatedSessionIds: Set<UUID> = []
    private let maxInvalidatedSessionsToTrack = 10
    
    /// Serial queue to ensure thread-safe operations
    private let operationQueue = DispatchQueue(label: "com.PomodoroPlus.notifications", qos: .userInitiated)
    
    override init() {
        super.init()
        notificationCenter.delegate = self
        checkPermission()
    }
    
    // MARK: - Permission
    
    func requestPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.hasPermission = granted
            }
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    func checkPermission() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.hasPermission = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Session Management
    
    /// Start a new notification session, invalidating all previous notifications
    func startNewSession() {
        operationQueue.sync {
            // Store old session ID as invalidated
            invalidatedSessionIds.insert(currentSessionId)
            
            // Trim old invalidated sessions to prevent unbounded growth
            while invalidatedSessionIds.count > maxInvalidatedSessionsToTrack {
                invalidatedSessionIds.remove(invalidatedSessionIds.first!)
            }
            
            // Cancel all notifications from previous session
            cancelAllInternal()
            
            // Generate new session ID
            currentSessionId = UUID()
            pendingIdentifiers.removeAll()
        }
    }
    
    /// Get the current session ID (thread-safe)
    private func getCurrentSessionId() -> UUID {
        return operationQueue.sync { currentSessionId }
    }
    
    /// Check if a session ID is valid (not invalidated)
    private func isSessionValid(_ sessionId: UUID) -> Bool {
        return operationQueue.sync {
            sessionId == currentSessionId && !invalidatedSessionIds.contains(sessionId)
        }
    }
    
    // MARK: - Scheduling
    
    /// Schedule a warning notification
    /// - Parameters:
    ///   - date: The date when the notification should fire
    ///   - phase: The current timer phase
    ///   - warningSeconds: The number of seconds before end (for display message)
    func scheduleWarning(at date: Date, phase: TimerPhase, warningSeconds: Int) {
        let timeInterval = date.timeIntervalSinceNow
        
        // Don't schedule if the date is in the past or too close
        guard timeInterval > 1 else {
            print("Warning notification skipped: date is in the past or too close")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Time Warning"
        
        // Dynamic message based on actual warning time
        let warningText = formatWarningTime(seconds: warningSeconds)
        content.body = "\(phase.displayName) ends in \(warningText)"
        content.categoryIdentifier = "TIMER_WARNING"
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false
        )
        
        // Get current session ID thread-safely
        let sessionId = getCurrentSessionId()
        
        // Include session ID in identifier to prevent stale notifications
        let identifier = "warning_\(phase.rawValue)_\(sessionId.uuidString)"
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        operationQueue.async { [weak self] in
            self?.pendingIdentifiers.insert(identifier)
        }
        
        notificationCenter.add(request) { [weak self] error in
            if let error = error {
                print("Failed to schedule warning notification: \(error)")
                self?.operationQueue.async {
                    self?.pendingIdentifiers.remove(identifier)
                }
            }
        }
    }
    
    /// Schedule a phase end notification
    /// - Parameters:
    ///   - date: The date when the phase ends
    ///   - phase: The current timer phase
    func schedulePhaseEnd(at date: Date, phase: TimerPhase) {
        let timeInterval = date.timeIntervalSinceNow
        
        // Don't schedule if the date is in the past or too close
        guard timeInterval > 1 else {
            print("End notification skipped: date is in the past or too close")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "\(phase.displayName) Complete"
        content.body = phase.isBreak ? "Break is over. Time to focus!" : "Great work! Time for a break."
        content.categoryIdentifier = "TIMER_END"
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false
        )
        
        // Get current session ID thread-safely
        let sessionId = getCurrentSessionId()
        
        // Include session ID in identifier to prevent stale notifications
        let identifier = "end_\(phase.rawValue)_\(sessionId.uuidString)"
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        operationQueue.async { [weak self] in
            self?.pendingIdentifiers.insert(identifier)
        }
        
        notificationCenter.add(request) { [weak self] error in
            if let error = error {
                print("Failed to schedule end notification: \(error)")
                self?.operationQueue.async {
                    self?.pendingIdentifiers.remove(identifier)
                }
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
    private func formatWarningTime(seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds == 0 {
                return minutes == 1 ? "1 minute" : "\(minutes) minutes"
            } else {
                return "\(minutes)m \(remainingSeconds)s"
            }
        } else {
            return "\(seconds) seconds"
        }
    }
    
    // MARK: - Cancellation
    
    /// Cancel all pending notifications for the current session
    func cancelAll() {
        operationQueue.async { [weak self] in
            self?.cancelAllInternal()
        }
    }
    
    private func cancelAllInternal() {
        // Cancel by specific identifiers first (more precise)
        if !pendingIdentifiers.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: Array(pendingIdentifiers))
            pendingIdentifiers.removeAll()
        }
        
        // Also remove all pending notifications as a safety measure
        notificationCenter.removeAllPendingNotificationRequests()
        
        // Also remove any delivered notifications from our app
        notificationCenter.removeAllDeliveredNotifications()
    }
    
    /// Cancel only warning notifications for the current session
    func cancelWarning() {
        operationQueue.async { [weak self] in
            guard let self = self else { return }
            let warningIdentifiers = self.pendingIdentifiers.filter { $0.hasPrefix("warning_") }
            if !warningIdentifiers.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: Array(warningIdentifiers))
                warningIdentifiers.forEach { self.pendingIdentifiers.remove($0) }
            }
        }
    }
    
    /// Cancel only end notifications for the current session
    func cancelEnd() {
        operationQueue.async { [weak self] in
            guard let self = self else { return }
            let endIdentifiers = self.pendingIdentifiers.filter { $0.hasPrefix("end_") }
            if !endIdentifiers.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: Array(endIdentifiers))
                endIdentifiers.forEach { self.pendingIdentifiers.remove($0) }
            }
        }
    }
    
    /// Extract session ID from notification identifier
    private func extractSessionId(from identifier: String) -> UUID? {
        // Identifiers are in format: "warning_phase_sessionId" or "end_phase_sessionId"
        let components = identifier.components(separatedBy: "_")
        guard components.count >= 3 else { return nil }
        // The session ID is everything after the second underscore
        let sessionIdString = components.dropFirst(2).joined(separator: "_")
        return UUID(uuidString: sessionIdString)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationScheduler: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        
        // Extract and verify session ID
        if let sessionId = extractSessionId(from: identifier) {
            if isSessionValid(sessionId) {
                // Valid notification for current session - show it
                completionHandler([.banner, .list])
            } else {
                // Stale notification from previous/invalidated session - don't show
                print("Suppressed stale notification (invalid session): \(identifier)")
                completionHandler([])
                
                // Also remove this notification from delivered list
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
            }
        } else {
            // Can't extract session ID, check if it's one of ours by prefix
            if identifier.hasPrefix("warning_") || identifier.hasPrefix("end_") {
                // It's ours but malformed - suppress for safety
                print("Suppressed malformed notification: \(identifier)")
                completionHandler([])
            } else {
                // Not our notification, let it through
                completionHandler([.banner, .list])
            }
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap if needed
        completionHandler()
    }
}
