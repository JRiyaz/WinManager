//
//  PermissionsManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices
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
        logger.info("Requesting Accessibility prompt")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func requestInputMonitoringPrompt() -> Bool {
        logger.info("Requesting Input Monitoring prompt")
        return CGRequestListenEventAccess()
    }

    static func requestAllPermissions() {
        if !hasAccessibility {
            requestAccessibilityPrompt()
        }
        if !hasInputMonitoring {
            requestInputMonitoringPrompt()
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openGeneralPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}

