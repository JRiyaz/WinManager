import AppKit
import ApplicationServices
import os

final class WindowCyclingManager {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.riyazjpersonalteam.WinManager",
        category: "WindowCycling"
    )
    
    private struct CycleState {
        // Keep a stable order instead of relying on the app's changing
        // Accessibility window order after every raise operation.
        var orderedWindows: [AXUIElement]
        var lastSelectedWindow: AXUIElement?
    }
    
    private var states: [pid_t: CycleState] = [:]
    private var terminationObserver: NSObjectProtocol?
    
    init() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }
            
            self?.states.removeValue(forKey: app.processIdentifier)
        }
    }
    
    deinit {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }
    
    /// Called by the event tap. Returns immediately so Accessibility requests
    /// don't run inside the synchronous event-tap callback.
    @discardableResult
    func handleHotkey(reverse: Bool) -> Bool {
        guard PermissionsManager.hasAccessibility,
              let app = NSWorkspace.shared.frontmostApplication,
              !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.cycleWindows(in: app, reverse: reverse)
        }
        
        // We accepted the shortcut. The paired key-up must also be suppressed.
        return true
    }
    
    func reset() {
        states.removeAll()
    }
    
    private func cycleWindows(
        in app: NSRunningApplication,
        reverse: Bool
    ) {
        guard PermissionsManager.hasAccessibility,
              !app.isTerminated else {
            return
        }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        _ = AXUIElementSetMessagingTimeout(appElement, 0.3)
        
        var windowsValue: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let rawWindows = windowsValue as? [AXUIElement] else {
            logger.debug("Could not retrieve windows for \(app.localizedName ?? "app")")
            return
        }
        
        let currentWindows = rawWindows.filter(isCyclableWindow)
        
        // A cycle requires at least two manageable windows.
        guard currentWindows.count > 1 else {
            states.removeValue(forKey: pid)
            return
        }
        
        var state = states[pid] ?? CycleState(
            orderedWindows: currentWindows,
            lastSelectedWindow: nil
        )
        
        // Remove closed/inaccessible windows from the cached sequence.
        state.orderedWindows.removeAll { cached in
            !currentWindows.contains { sameWindow($0, cached) }
        }
        
        // Add newly opened windows without reordering existing ones.
        for window in currentWindows {
            if !state.orderedWindows.contains(where: { sameWindow($0, window) }) {
                state.orderedWindows.append(window)
            }
        }
        
        let windows = state.orderedWindows
        
        guard windows.count > 1 else {
            states.removeValue(forKey: pid)
            return
        }
        
        let focusedWindow = windowAttribute(
            kAXFocusedWindowAttribute,
            from: appElement
        )
        
        let mainWindow = windowAttribute(
            kAXMainWindowAttribute,
            from: appElement
        )
        
        // Prefer the actual focus, then the last selected window, then
        // the app's main window. The first window is the final fallback.
        let currentIndex =
        index(of: focusedWindow, in: windows)
        ?? index(of: state.lastSelectedWindow, in: windows)
        ?? index(of: mainWindow, in: windows)
        ?? 0
        
        let count = windows.count
        
        let targetIndex: Int
        if reverse {
            targetIndex = (currentIndex - 1 + count) % count
        } else {
            targetIndex = (currentIndex + 1) % count
        }
        
        let target = windows[targetIndex]
        
        guard let isMinimized = minimizedState(of: target) else {
            states[pid] = state
            return
        }
        
        var restoredSuccessfully = false
        
        // Restore the selected window if it is minimized.
        if isMinimized {
            let result = AXUIElementSetAttributeValue(
                target,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
            
            guard result == .success else {
                logger.debug("Could not restore the selected window")
                states[pid] = state
                return
            }
            
            restoredSuccessfully = true
        }
        
        if app.isHidden {
            _ = app.unhide()
        }
        
        let activated = app.activate(
            options: [.activateIgnoringOtherApps]
        )
        
        let raised = AXUIElementPerformAction(
            target,
            kAXRaiseAction as CFString
        ) == .success
        
        // Advance our remembered selection only if some relevant operation
        // succeeded. A failed restore must not be treated as a successful cycle.
        if restoredSuccessfully || activated || raised {
            state.lastSelectedWindow = target
        }
        
        states[pid] = state
        
        logger.debug(
            "Window cycle requested for \(app.localizedName ?? "app")"
        )
    }
    
    private func isCyclableWindow(_ window: AXUIElement) -> Bool {
        _ = AXUIElementSetMessagingTimeout(window, 0.3)
        
        var roleValue: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(
            window,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success,
              let role = roleValue as? String,
              role == (kAXWindowRole as String) else {
            return false
        }
        
        var subroleValue: CFTypeRef?
        
        if AXUIElementCopyAttributeValue(
            window,
            kAXSubroleAttribute as CFString,
            &subroleValue
        ) == .success,
           let subrole = subroleValue as? String {
            if subrole == (kAXSystemDialogSubrole as String)
                || subrole == (kAXFloatingWindowSubrole as String) {
                return false
            }
        }
        
        // Include minimized windows, but skip windows whose minimized state
        // cannot be read reliably.
        return minimizedState(of: window) != nil
    }
    
    private func minimizedState(of window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        
        return value as? Bool
    }
    
    private func windowAttribute(
        _ attribute: String,
        from appElement: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(
            appElement,
            attribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    
    private func index(
        of target: AXUIElement?,
        in windows: [AXUIElement]
    ) -> Int? {
        guard let target else { return nil }
        
        return windows.firstIndex {
            sameWindow($0, target)
        }
    }
    
    private func sameWindow(
        _ lhs: AXUIElement,
        _ rhs: AXUIElement
    ) -> Bool {
        CFEqual(lhs, rhs)
    }
}
