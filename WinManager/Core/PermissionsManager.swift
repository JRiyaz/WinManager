//
//  PermissionsManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices
import CoreGraphics
import os

enum PermissionsManager {
    private static let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "Permissions")
    
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }
    
    static var hasInputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }
    
    static var allGranted: Bool {
        hasAccessibility && hasInputMonitoring
    }
    
    @discardableResult
    static func requestAccessibilityPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        logger.info("Accessibility trusted: \(trusted)")
        return trusted
    }
    
    @discardableResult
    static func requestInputMonitoringPrompt() -> Bool {
        let granted = CGRequestListenEventAccess()
        logger.info("Input Monitoring granted: \(granted)")
        return granted
    }
    
    static func requestMissingPermissionsOnLaunch() {
        // These APIs ask macOS to request access; neither API can override a
        // previous denial or guarantee a prompt appears every time.
        if !hasAccessibility {
            _ = requestAccessibilityPrompt()
        }
        if !hasInputMonitoring {
            _ = requestInputMonitoringPrompt()
        }
    }
    
    static func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    
    static func openInputMonitoringSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }
    
    static func openGeneralPrivacySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security")
    }
    
    private static func openSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
