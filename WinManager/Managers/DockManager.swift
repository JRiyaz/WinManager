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
        var element: AXUIElement?
        
        // 1. Get the exact UI element under the cursor
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, var candidate = element else { return false }
        
        // 2. Verify the element belongs to the Dock process
        var clickedPID: pid_t = 0
        AXUIElementGetPid(candidate, &clickedPID)
        
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              dockApp.processIdentifier == clickedPID else {
            return false // We clicked something else on the screen
        }
        
        // 3. Traverse up the Accessibility tree to find the specific app icon
        for _ in 0..<6 {
            if let app = application(for: candidate),
               let frontmost = NSWorkspace.shared.frontmostApplication,
               app.processIdentifier == frontmost.processIdentifier {
                
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
        
        var isMinimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized) == .success,
           let minimized = isMinimized as? Bool, minimized == true {
            return false
        }
        
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        return true
    }
}
