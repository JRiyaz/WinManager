//
//  WindowCloseManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices

final class WindowCloseManager {
    private var timer: Timer?

    func start() {
        // Polls the frontmost app once per second. Incredibly lightweight and avoids dropped AX notifications.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkFrontmostApp()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkFrontmostApp() {
        guard UserDefaults.standard.bool(forKey: "enableAutoQuit"),
              let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular,
              app.bundleIdentifier != "com.apple.finder",
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?

        // If the array doesn't exist, the app has no windows open
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            app.terminate()
            return
        }

        // Count only actual standard windows (ignoring hidden background rendering layers)
        var standardCount = 0
        for window in windows {
            var subrole: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success,
               (subrole as? String) == (kAXStandardWindowSubrole as String) {
                standardCount += 1
            }
        }

        if standardCount == 0 {
            app.terminate()
        }
    }
}
