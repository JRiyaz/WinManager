//
//  DockManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices
import os

final class DockManager {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "Dock")
    private let systemWide = AXUIElementCreateSystemWide()
    private var cachedDockPID: pid_t?

    private var dockPID: pid_t? {
        if let cached = cachedDockPID,
           let app = NSRunningApplication(processIdentifier: cached),
           !app.isTerminated {
            return cached
        }
        let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        cachedDockPID = dock?.processIdentifier
        return cachedDockPID
    }

    func handleMouseDown(_ event: CGEvent) -> Bool {
        guard PermissionsManager.hasAccessibility else { return false }

        let point = event.location

        // 1. Cheap geometric pre-filter: Check if point is near any screen edge (Dock region).
        // If the click is in the middle of a screen, avoid expensive Accessibility queries entirely.
        guard isPointNearScreenEdge(point) else {
            return false
        }

        // 2. Fast check: Identify the UI element under cursor and verify it belongs to Dock PID
        guard let targetDockPID = dockPID else { return false }

        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, var candidate = element else { return false }

        var clickedPID: pid_t = 0
        guard AXUIElementGetPid(candidate, &clickedPID) == .success, clickedPID == targetDockPID else {
            return false // Element does not belong to the Dock
        }

        // 3. Bounded traversal to find the clicked application icon
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }

        for _ in 0..<4 {
            if let app = application(for: candidate), app.processIdentifier == frontmost.processIdentifier {
                logger.info("Dock click on frontmost app (\(app.localizedName ?? "app")). Minimizing.")
                return minimizeFrontmostApplication()
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parent = parentValue,
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            candidate = (parent as! AXUIElement)
        }

        return false
    }

    private func isPointNearScreenEdge(_ point: CGPoint) -> Bool {
        let margin: CGFloat = 120.0
        for screen in NSScreen.screens {
            let frame = screen.frame
            // Check if point is near bottom, left, or right edges of the display
            let inBottom = point.y <= frame.minY + margin
            let inLeft = point.x <= frame.minX + margin
            let inRight = point.x >= frame.maxX - margin
            if frame.contains(point) && (inBottom || inLeft || inRight) {
                return true
            }
        }
        return false
    }

    private func application(for element: AXUIElement) -> NSRunningApplication? {
        for attribute in [kAXURLAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let string = value as? String, !string.isEmpty else { continue }

            if attribute == kAXURLAttribute,
               let url = URL(string: string),
               let bundleID = Bundle(url: url)?.bundleIdentifier,
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                return app
            }

            if let app = NSWorkspace.shared.runningApplications.first(where: {
                ($0.localizedName ?? "").localizedCaseInsensitiveCompare(string) == .orderedSame
            }) {
                return app
            }
        }
        return nil
    }

    private func minimizeFrontmostApplication() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement],
              let window = windows.first else {
            // Fallback: hide the application if no windows can be directly minimized
            app.hide()
            return true
        }

        var isMinimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized) == .success,
           let minimized = isMinimized as? Bool, minimized == true {
            return false
        }

        let setResult = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        if setResult != .success {
            app.hide()
        }
        return true
    }
}

