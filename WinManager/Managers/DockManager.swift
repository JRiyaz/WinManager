import AppKit
import ApplicationServices
import CoreGraphics

final class DockManager {
    private let systemWide = AXUIElementCreateSystemWide()
    private var cachedDockPID: pid_t?
    
    func handleMouseDown(_ event: CGEvent) -> Bool {
        guard PermissionsManager.hasAccessibility else { return false }
        
        // CGEvent/Accessibility coordinates are global Quartz coordinates. Use CGDisplayBounds
        // rather than NSScreen.main so edge filtering works on external displays too.
        let point = event.location
        guard isPointNearAnyDisplayEdge(point), let dockPID = dockProcessID else { return false }
        
        var elementValue: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &elementValue
        ) == .success, var candidate = elementValue else { return false }
        
        var ownerPID: pid_t = 0
        guard AXUIElementGetPid(candidate, &ownerPID) == .success, ownerPID == dockPID else {
            return false
        }
        
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        
        // Traverse only a small, bounded number of parents to find the Dock item.
        for _ in 0..<6 {
            if let targetApp = application(for: candidate),
               targetApp.processIdentifier == frontmost.processIdentifier {
                return minimizeFrontmostApplication()
            }
            
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                candidate,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else { break }
            candidate = parentValue as! AXUIElement
        }
        
        return false
    }
    
    private var dockProcessID: pid_t? {
        if let cachedDockPID,
           let app = NSRunningApplication(processIdentifier: cachedDockPID),
           !app.isTerminated {
            return cachedDockPID
        }
        
        cachedDockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        return cachedDockPID
    }
    
    private func isPointNearAnyDisplayEdge(_ point: CGPoint) -> Bool {
        let margin: CGFloat = 110
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard bounds.contains(point) else { continue }
            
            if point.x <= bounds.minX + margin
                || point.x >= bounds.maxX - margin
                || point.y <= bounds.minY + margin
                || point.y >= bounds.maxY - margin {
                return true
            }
        }
        return false
    }
    
    private func application(for element: AXUIElement) -> NSRunningApplication? {
        for attribute in [kAXURLAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let string = value as? String,
                  !string.isEmpty else { continue }
            
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
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let windows = windowsValue as? [AXUIElement],
              !windows.isEmpty else { return false }
        
        // Prefer the focused window so the click minimizes the window the user is working in.
        var targetWindow: AXUIElement?
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        ) == .success,
           let focusedValue,
           CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            // The CF type ID was checked above, so bridge the validated value.
            targetWindow = unsafeBitCast(focusedValue, to: AXUIElement.self)
        }
        targetWindow = targetWindow ?? windows.first
        guard let window = targetWindow else { return false }
        
        var minimizedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &minimizedValue
        ) == .success,
           (minimizedValue as? Bool) == true {
            // Let Dock/macOS handle clicks on an already minimized app normally.
            return false
        }
        
        return AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        ) == .success
    }
}
