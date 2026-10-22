import AppKit
import ApplicationServices
import CoreGraphics

enum DockClickBehavior: String {
    case sequential = "sequential"
    case allAtOnce = "allAtOnce"
}

final class DockManager {
    private let systemWide = AXUIElementCreateSystemWide()
    private var cachedDockPID: pid_t?
    private var terminationObserver: NSObjectProtocol?
    
    // MARK: - Sequential Mode State
    private struct SequentialAppState {
        enum Phase {
            case minimize
            case restore
        }
        var phase: Phase = .minimize
        var minimizedOrder: [AXUIElement] = []
    }
    
    private var sequentialStates: [pid_t: SequentialAppState] = [:]
    
    init() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.sequentialStates.removeValue(forKey: app.processIdentifier)
        }
    }
    
    deinit {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }
    
    // MARK: - Event Tap Entry Point
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
        
        // Traverse only a small, bounded number of parents to find the Dock item.
        for _ in 0..<6 {
            if let targetApp = application(for: candidate) {
                return toggleApplicationWindows(targetApp)
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
    
    // MARK: - Dispatcher
    private func toggleApplicationWindows(_ targetApp: NSRunningApplication) -> Bool {
        guard !targetApp.isTerminated else { return false }
        
        let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let rawWindows = windowsValue as? [AXUIElement],
              !rawWindows.isEmpty else {
            // App has no open windows -> let native macOS Dock handle click (e.g. reopen/create window).
            return false
        }
        
        let windows = rawWindows.filter { isEligibleWindow($0) }
        guard !windows.isEmpty else { return false }
        
        let modeString = UserDefaults.standard.string(forKey: "dockClickBehavior") ?? "sequential"
        let mode = DockClickBehavior(rawValue: modeString) ?? .sequential
        
        switch mode {
        case .sequential:
            return handleSequentialClick(targetApp, appElement: appElement, windows: windows)
        case .allAtOnce:
            return handleAllAtOnceClick(targetApp, appElement: appElement, windows: windows)
        }
    }
    
    // MARK: - Mode A: Sequential
    private func handleSequentialClick(
        _ targetApp: NSRunningApplication,
        appElement: AXUIElement,
        windows: [AXUIElement]
    ) -> Bool {
        let pid = targetApp.processIdentifier
        let (unminimized, minimized) = classifyWindows(windows)
        let isFrontmost = (NSWorkspace.shared.frontmostApplication?.processIdentifier == pid)
        
        // Handle inactive target app first: activate it instead of minimizing
        if !isFrontmost {
            if !unminimized.isEmpty {
                let activated = targetApp.activate(options: [.activateIgnoringOtherApps])
                var raised = false
                if let preferred = preferredWindow(for: appElement) ?? unminimized.first {
                    raised = (AXUIElementPerformAction(preferred, kAXRaiseAction as CFString) == .success)
                }
                return activated || raised
            } else if !minimized.isEmpty {
                var state = sequentialStates[pid] ?? SequentialAppState()
                reconcileSequentialState(&state, currentMinimized: minimized)
                
                guard let windowToRestore = state.minimizedOrder.last ?? minimized.last else {
                    return false
                }
                
                if AXUIElementSetAttributeValue(windowToRestore, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success {
                    state.minimizedOrder.removeAll { areEqual($0, windowToRestore) }
                    targetApp.activate(options: [.activateIgnoringOtherApps])
                    _ = AXUIElementPerformAction(windowToRestore, kAXRaiseAction as CFString)
                    
                    let remaining = minimized.filter { !areEqual($0, windowToRestore) }
                    state.phase = remaining.isEmpty ? .minimize : .restore
                    sequentialStates[pid] = state
                    return true
                }
                return false
            }
            return false
        }
        
        // Target app is ACTIVE: run sequential state machine
        var state = sequentialStates[pid] ?? SequentialAppState()
        reconcileSequentialState(&state, currentMinimized: minimized)
        
        // Reconcile phase against real state
        if unminimized.isEmpty {
            state.phase = .restore
        } else if minimized.isEmpty {
            state.phase = .minimize
        }
        
        if state.phase == .minimize {
            // MINIMIZE PHASE: Minimize the focused unminimized window
            guard let windowToMinimize = focusedWindow(for: appElement, within: unminimized) ?? unminimized.first else {
                return false
            }
            
            // Track successful changes only
            if AXUIElementSetAttributeValue(windowToMinimize, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                state.minimizedOrder.removeAll { areEqual($0, windowToMinimize) }
                state.minimizedOrder.append(windowToMinimize)
                
                // Focus the next available unminimized window
                let remaining = unminimized.filter { !areEqual($0, windowToMinimize) }
                if let nextWindow = remaining.first {
                    _ = AXUIElementPerformAction(nextWindow, kAXRaiseAction as CFString)
                    state.phase = .minimize
                } else {
                    // Last visible window minimized -> switch to restore phase
                    state.phase = .restore
                }
                
                sequentialStates[pid] = state
                return true
            }
            return false
        } else {
            // RESTORE PHASE: Restore the most recently minimized window
            guard let windowToRestore = state.minimizedOrder.last ?? minimized.last else {
                state.phase = .minimize
                sequentialStates[pid] = state
                return false
            }
            
            if AXUIElementSetAttributeValue(windowToRestore, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success {
                // Remove only on successful restore
                state.minimizedOrder.removeAll { areEqual($0, windowToRestore) }
                targetApp.activate(options: [.activateIgnoringOtherApps])
                _ = AXUIElementPerformAction(windowToRestore, kAXRaiseAction as CFString)
                
                let remainingMinimized = minimized.filter { !areEqual($0, windowToRestore) }
                state.phase = (remainingMinimized.isEmpty || state.minimizedOrder.isEmpty) ? .minimize : .restore
                sequentialStates[pid] = state
                return true
            } else {
                // Restore failed: preserve failed window in stack
                return false
            }
        }
    }
    
    // MARK: - Mode B: All Windows
    private func handleAllAtOnceClick(
        _ targetApp: NSRunningApplication,
        appElement: AXUIElement,
        windows: [AXUIElement]
    ) -> Bool {
        let (unminimized, minimized) = classifyWindows(windows)
        let isFrontmost = (NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier)
        
        if isFrontmost && !unminimized.isEmpty {
            var anyMinimized = false
            for window in unminimized {
                if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                    anyMinimized = true
                }
            }
            return anyMinimized
        } else {
            var anyRestored = false
            for window in minimized.reversed() {
                if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success {
                    anyRestored = true
                }
            }
            
            let activated = targetApp.activate(options: [.activateIgnoringOtherApps])
            var raised = false
            let preferred = preferredWindow(for: appElement) ?? unminimized.first ?? minimized.first
            if let preferred {
                raised = (AXUIElementPerformAction(preferred, kAXRaiseAction as CFString) == .success)
            }
            
            return anyRestored || activated || raised
        }
    }
    
    // MARK: - State Reconciliation
    private func reconcileSequentialState(_ state: inout SequentialAppState, currentMinimized: [AXUIElement]) {
        // Remove stale entries not in currentMinimized
        state.minimizedOrder.removeAll { orderItem in
            !currentMinimized.contains { areEqual($0, orderItem) }
        }
        
        // Deterministically prepend unrecorded minimized windows
        for minWin in currentMinimized {
            if !state.minimizedOrder.contains(where: { areEqual($0, minWin) }) {
                state.minimizedOrder.insert(minWin, at: 0)
            }
        }
    }
    
    // MARK: - Common Helpers
    private func classifyWindows(_ windows: [AXUIElement]) -> (unminimized: [AXUIElement], minimized: [AXUIElement]) {
        var unminimized: [AXUIElement] = []
        var minimized: [AXUIElement] = []
        
        for window in windows {
            var minVal: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minVal) == .success,
                  let isMinimized = minVal as? Bool else {
                continue
            }
            if isMinimized {
                minimized.append(window)
            } else {
                unminimized.append(window)
            }
        }
        return (unminimized, minimized)
    }
    
    private func isEligibleWindow(_ window: AXUIElement) -> Bool {
        var roleVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleVal) == .success,
              let role = roleVal as? String, role == (kAXWindowRole as String) else {
            return false
        }
        
        var subroleVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleVal) == .success,
           let subrole = subroleVal as? String {
            // Exclude system dialogs and floating utility palettes
            if subrole == (kAXSystemDialogSubrole as String) ||
                subrole == (kAXFloatingWindowSubrole as String) {
                return false
            }
        }
        
        var minVal: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minVal) == .success
    }
    
    private func focusedWindow(for appElement: AXUIElement, within candidates: [AXUIElement]) -> AXUIElement? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
            let focused = unsafeBitCast(value, to: AXUIElement.self)
            if candidates.contains(where: { areEqual($0, focused) }) {
                return focused
            }
        }
        return nil
    }
    
    private func preferredWindow(for appElement: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                return unsafeBitCast(value, to: AXUIElement.self)
            }
        }
        return nil
    }
    
    private func areEqual(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
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
}
