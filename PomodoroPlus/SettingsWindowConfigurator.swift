import SwiftUI
import AppKit

/// Configures the SwiftUI Settings window to float above other windows and
/// automatically close when it loses focus.
struct SettingsWindowConfigurator: NSViewRepresentable {
    
    class Coordinator: NSObject {
        var observer: NSObjectProtocol?
        var activationObserver: NSObjectProtocol?
        weak var window: NSWindow?
        var isConfigured = false
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        
        // Delay configuration to ensure window is ready
        DispatchQueue.main.async {
            self.configureWindowIfNeeded(view: view, context: context)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindowIfNeeded(view: nsView, context: context)
    }
    
    private func configureWindowIfNeeded(view: NSView, context: Context) {
        guard !context.coordinator.isConfigured,
              let window = view.window else {
            return
        }
        
        context.coordinator.isConfigured = true
        context.coordinator.window = window
        
        // Configure window properties
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        
        // Bring to front and activate
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
        
        // Close when clicking outside (resign key)
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            // Small delay to allow other UI interactions
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let window = window else { return }

                // If the settings window has an attached sheet (e.g., alert, open panel), do not close.
                if window.attachedSheet != nil { return }

                // If the current key or modal window is a sheet presented by this window, do not close.
                if let key = NSApp.keyWindow, key.sheetParent == window { return }
                if let modal = NSApp.modalWindow, modal.sheetParent == window { return }

                // Only close if window is still not key (user didn't click back)
                if !window.isKeyWindow {
                    window.close()
                }
            }
        }
        
        // Also observe app deactivation to close settings
        context.coordinator.activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak window] _ in
            // Don't close immediately - the user might be switching to another app temporarily
            // Only close if the settings window loses key status
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let activationObserver = coordinator.activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        coordinator.window = nil
        coordinator.isConfigured = false
    }
}
