//
//  WindowCloseManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices
import os

final class WindowCloseManager {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "WindowClose")
    private var timer: Timer?

    // Tracks previously observed window counts per PID so we only trigger when an app
    // transitions from having open windows to zero windows (i.e., user closed the last window).
    private var lastKnownWindowCount: [pid_t: Int] = [:]

    // Apps that should never be automatically terminated
    private let excludedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.Music",
        "com.apple.dt.Xcode",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.apple.ActivityMonitor"
    ]

    func start() {
        guard timer == nil else { return }

        logger.info("Starting safe WindowCloseManager polling timer")
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkFrontmostApp()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastKnownWindowCount.removeAll()
        logger.info("Stopped WindowCloseManager polling timer")
    }

    private func checkFrontmostApp() {
        guard UserDefaults.standard.bool(forKey: "enableAutoQuit"),
              PermissionsManager.hasAccessibility,
              let app = NSWorkspace.shared.frontmostApplication,
              !app.isTerminated,
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        if let bundleID = app.bundleIdentifier, excludedBundleIdentifiers.contains(bundleID) {
            return
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?

        // If Accessibility query fails or is not accessible, treat as UNKNOWN state.
        // NEVER terminate an app on an API error or timeout!
        let axResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard axResult == .success, let windows = windowsValue as? [AXUIElement] else {
            // State is indeterminate - do not touch the application
            return
        }

        // Count only actual standard, non-hidden windows
        var standardCount = 0
        for window in windows {
            var subrole: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success,
               (subrole as? String) == (kAXStandardWindowSubrole as String) {
                standardCount += 1
            }
        }

        let previousCount = lastKnownWindowCount[pid] ?? 0
        lastKnownWindowCount[pid] = standardCount

        // Only terminate if the app previously had open windows and now has 0 windows
        // (confirming the user actively closed the last window, rather than an app that is windowless by design).
        if previousCount > 0 && standardCount == 0 {
            logger.notice("Detected last window closed for \(app.localizedName ?? "app") (PID: \(pid)). Terminating app.")
            lastKnownWindowCount.removeValue(forKey: pid)
            app.terminate()
        }
    }
}

