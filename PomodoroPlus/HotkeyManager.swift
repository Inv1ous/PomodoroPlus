import Foundation
import Carbon
import AppKit

/// Manages global hotkeys for timer control
class HotkeyManager {
    
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    
    private weak var timerEngine: TimerEngine?
    private weak var alarmPlayer: AlarmPlayer?
    
    // Hotkey IDs
    private let startPauseHotkeyID: UInt32 = 1
    private let stopAlarmHotkeyID: UInt32 = 2
    private let skipPhaseHotkeyID: UInt32 = 3
    
    init(timerEngine: TimerEngine, alarmPlayer: AlarmPlayer) {
        self.timerEngine = timerEngine
        self.alarmPlayer = alarmPlayer
    }
    
    deinit {
        unregisterHotkeys()
    }
    
    // MARK: - Registration
    
    func registerHotkeys() {
        // Request accessibility permissions if needed
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        if !trusted {
            print("Accessibility permissions required for global hotkeys")
            // Continue anyway - hotkeys might still work in some cases
        }
        
        // Install event handler
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handlerBlock: EventHandlerProcPtr = { (nextHandler, event, userData) -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if err == noErr {
                HotkeyManager.handleHotkey(hotKeyID.id)
            }
            
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerBlock,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )
        
        // Register individual hotkeys
        // Cmd+Shift+P for Start/Pause
        registerHotkey(
            id: startPauseHotkeyID,
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        
        // Cmd+Shift+S for Stop Alarm
        registerHotkey(
            id: stopAlarmHotkeyID,
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        
        // Cmd+Shift+K for Skip Phase
        registerHotkey(
            id: skipPhaseHotkeyID,
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        
        // Store references in shared instance for callback
        HotkeyManager.sharedInstance = self
    }
    
    private func registerHotkey(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x414450) // "ADP" for PomodoroPlus
        hotKeyID.id = id
        
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
        } else {
            print("Failed to register hotkey \(id): \(status)")
        }
    }
    
    func unregisterHotkeys() {
        for ref in hotKeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
        
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        
        HotkeyManager.sharedInstance = nil
    }
    
    // MARK: - Static Handler
    
    private static weak var sharedInstance: HotkeyManager?
    
    private static func handleHotkey(_ id: UInt32) {
        DispatchQueue.main.async {
            guard let instance = sharedInstance else { return }
            
            switch id {
            case instance.startPauseHotkeyID:
                instance.timerEngine?.toggleStartPause()
            case instance.stopAlarmHotkeyID:
                instance.alarmPlayer?.stop()
            case instance.skipPhaseHotkeyID:
                instance.timerEngine?.skip()
            default:
                break
            }
        }
    }
}
