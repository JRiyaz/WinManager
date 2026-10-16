//
//  WindowCloseManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices

/// Tracks windows for the currently active app and politely requests termination
/// after its last observed window is destroyed. Accessibility notifications are best-effort.
final class WindowCloseManager {
    private var workspaceObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindows: [pid_t: Set<String>] = [:]
    private var appByPID: [pid_t: NSRunningApplication] = [:]

    func start() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.observe(app)
        }
        
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            
            if let observer = self?.observers[pid] {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            self?.observers.removeValue(forKey: pid)
            self?.observedWindows.removeValue(forKey: pid)
            self?.appByPID.removeValue(forKey: pid)
        }
        
        if let app = NSWorkspace.shared.frontmostApplication {
            observe(app)
        }
    }

    func stop() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
        workspaceObserver = nil
        terminationObserver = nil
        
        for (_, observer) in observers {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        observedWindows.removeAll()
        appByPID.removeAll()
    }

    private func observe(_ app: NSRunningApplication) {
        guard UserDefaults.standard.bool(forKey: "enableAutoQuit"),
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "com.apple.finder",
              !app.isTerminated,
              PermissionsManager.hasAccessibility else { return }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        
        // Capture the observer to find the PID later
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let refcon else { return }
            let manager = Unmanaged<WindowCloseManager>.fromOpaque(refcon).takeUnretainedValue()
            
            // Reverse lookup the PID attached to this specific observer
            guard let pid = manager.observers.first(where: { $0.value == observer })?.key else { return }
            manager.windowDestroyed(element: element, notification: notification as String, pid: pid)
        }
        
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        observers[pid] = observer
        appByPID[pid] = app
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else { return }

        var identifiers = Set<String>()
        for window in windows {
            let identifier = windowIdentifier(window)
            identifiers.insert(identifier)
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
        }
        observedWindows[pid] = identifiers
    }

    private func windowDestroyed(element: AXUIElement, notification: String, pid: pid_t) {
        guard notification == (kAXUIElementDestroyedNotification as String) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.recheckApp(pid: pid)
        }
    }

    private func recheckApp(pid: pid_t) {
        guard UserDefaults.standard.bool(forKey: "enableAutoQuit"),
      let app = NSRunningApplication(processIdentifier: pid),
      !app.isTerminated else { return }

        let element = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            app.terminate()
            return
        }

        // Filter out hidden dummy windows (like Chrome/Safari background processes)
        var standardWindowCount = 0
        for window in windows {
            var subrole: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole) == .success,
               (subrole as? String) == (kAXStandardWindowSubrole as String) {
                standardWindowCount += 1
            }
        }

        if standardWindowCount == 0 {
            app.terminate()
        }
    }

    private func windowIdentifier(_ window: AXUIElement) -> String {
        var titleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String {
            return title
        }
        return UUID().uuidString
    }
}
