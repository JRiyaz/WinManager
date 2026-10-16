//
//  DockManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices
import CoreGraphics
import os

final class DockManager {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "Dock")
    private let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
    }()
    private var cachedDockPID: pid_t?
    
    private var dockPID: pid_t? {
        if let cachedDockPID,
           let app = NSRunningApplication(processIdentifier: cachedDockPID),
           !app.isTerminated {
            return cachedDockPID
        }
        cachedDockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        return cachedDockPID
    }
    
    /// Returns true only when the click belongs to the Dock item for the app
    /// that is already frontmost and a window was successfully minimized.
    func handleMouseDown(_ event: CGEvent) -> Bool {
        guard PermissionsManager.hasAccessibility else { return false }
        guard isNearDockRegion(NSEvent.mouseLocation) else { return false }
        guard let targetDockPID = dockPID else { return false }
        
        let point = event.location
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              var candidate = element else {
            return false
        }
        
        var clickedPID: pid_t = 0
        guard AXUIElementGetPid(candidate, &clickedPID) == .success,
              clickedPID == targetDockPID,
              let frontmost = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        for _ in 0..<4 {
            AXUIElementSetMessagingTimeout(candidate, 0.1)
            if let clickedApplication = application(for: candidate),
               clickedApplication.processIdentifier == frontmost.processIdentifier {
                let didMinimize = minimizeFrontmostApplication(frontmost)
                if didMinimize {
                    logger.debug("Minimized frontmost app after its Dock icon was clicked")
                }
                return didMinimize
            }
            
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                break
            }
            candidate = parentValue as! AXUIElement
        }
        
        return false
    }
    
    private func isNearDockRegion(_ point: NSPoint) -> Bool {
        let margin: CGFloat = 100
        for screen in NSScreen.screens {
            let frame = screen.frame
            guard frame.contains(point) else { continue }
            if point.y <= frame.minY + margin ||
                point.x <= frame.minX + margin ||
                point.x >= frame.maxX - margin {
                return true
            }
        }
        return false
    }
    
    private func application(for element: AXUIElement) -> NSRunningApplication? {
        var urlValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlValue) == .success,
           let urlValue {
            let url: URL?
            if let bridgedURL = urlValue as? URL {
                url = bridgedURL
            } else if let string = urlValue as? String {
                url = URL(string: string)
            } else {
                url = nil
            }
            
            if let url, let bundleID = Bundle(url: url)?.bundleIdentifier,
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                return app
            }
        }
        
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let title = value as? String,
                  !title.isEmpty else {
                continue
            }
            
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                ($0.localizedName ?? "").localizedCaseInsensitiveCompare(title) == .orderedSame
            }) {
                return app
            }
        }
        
        return nil
    }
    
    private func minimizeFrontmostApplication(_ app: NSRunningApplication) -> Bool {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.1)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            // Do not silently convert a failed minimize into Hide; keep Dock's
            // native behavior whenever we cannot prove a minimize succeeded.
            return false
        }
        
        for window in windows {
            AXUIElementSetMessagingTimeout(window, 0.1)
            var subroleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                  (subroleValue as? String) == (kAXStandardWindowSubrole as String) else {
                continue
            }
            
            var settable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success,
                  settable.boolValue else {
                continue
            }
            
            var isMinimizedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimizedValue) == .success,
               let isMinimized = isMinimizedValue as? Bool,
               isMinimized {
                // Clicking a minimized app should restore it using the native Dock action.
                return false
            }
            
            if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                return true
            }
        }
        return false
    }
}
