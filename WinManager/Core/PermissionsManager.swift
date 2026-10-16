//
//  PermissionsManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices

enum PermissionsManager {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var hasInputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestAccessibilityPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestInputMonitoringPrompt() -> Bool {
        CGRequestListenEventAccess()
    }

    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else { return }
        NSWorkspace.shared.open(url)
    }
}
