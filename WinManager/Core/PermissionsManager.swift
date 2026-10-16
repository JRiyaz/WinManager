import AppKit
import ApplicationServices

enum PermissionsManager {
    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    
    static var hasInputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }
    
    @discardableResult
    static func requestAccessibilityPrompt() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    @discardableResult
    static func requestInputMonitoringPrompt() -> Bool {
        CGRequestListenEventAccess()
    }
    
    static func openAccessibilitySettings() {
        openSettings(anchor: "Privacy_Accessibility")
    }
    
    static func openInputMonitoringSettings() {
        openSettings(anchor: "Privacy_ListenEvent")
    }
    
    static func openPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        
        // Fallback: open System Settings itself if the deep link isn't accepted.
        let settingsApp = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        _ = NSWorkspace.shared.open(settingsApp)
    }
    
    private static func openSettings(anchor: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
            return
        }
        openPrivacySettings()
    }
}
