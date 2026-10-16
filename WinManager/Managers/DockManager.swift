//
//  DockManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices

final class DockManager {
    private let systemWide = AXUIElementCreateSystemWide()

    func handleMouseDown(_ event: CGEvent) -> Bool {
        guard PermissionsManager.hasAccessibility else { return false }

        let point = event.location
        guard let screen = NSScreen.main else { return false }
        
        let isNearBottom = point.y > (screen.frame.height - 100)
        guard isNearBottom else { return false }

        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, var candidate = element else { return false }

        for _ in 0..<6 {
            if let app = application(for: candidate),
               let frontmost = NSWorkspace.shared.frontmostApplication,
               app.processIdentifier == frontmost.processIdentifier {
                
                // Only consume the click if we actually successfully minimized an active window
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
              let window = windows.first else { return false }
              
        // Check if the window is ALREADY minimized
        var isMinimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized) == .success,
           let minimized = isMinimized as? Bool, minimized == true {
            // Return false so macOS handles the click and un-minimizes the window naturally
            return false
        }
        
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        return true
    }
}
