import AppKit
import ApplicationServices

/// Event-driven, best-effort quit-on-close implementation.
/// It only terminates after a standard window was observed and a successful
/// Accessibility query confirms no standard windows remain. Query errors never mean zero windows.
final class WindowCloseManager {
    private var workspaceObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var observers: [pid_t: AXObserver] = [:]
    private var hadStandardWindow: Set<pid_t> = []
    
    // Finder is the macOS shell and should normally remain running when its last
    // Finder window closes. Other regular apps are handled by this feature.
    private let excludedBundleIdentifiers: Set<String> = ["com.apple.finder"]
    
    func start() {
        guard workspaceObserver == nil,
              UserDefaults.standard.bool(forKey: "enableAutoQuit"),
              PermissionsManager.hasAccessibility else { return }
        
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
            self?.removeObserver(for: app.processIdentifier)
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
        
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        hadStandardWindow.removeAll()
    }
    
    private func observe(_ app: NSRunningApplication) {
        guard UserDefaults.standard.bool(forKey: "enableAutoQuit"),
              PermissionsManager.hasAccessibility,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !app.isTerminated,
              app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier,
              !excludedBundleIdentifiers.contains(bundleID) else { return }
        
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }
        
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            guard let refcon else { return }
            let manager = Unmanaged<WindowCloseManager>.fromOpaque(refcon).takeUnretainedValue()
            guard let pid = manager.observers.first(where: { $0.value == observer })?.key else { return }
            manager.handleAccessibilityNotification(
                notification: notification as String,
                pid: pid
            )
        }
        
        var observerValue: AXObserver?
        guard AXObserverCreate(pid, callback, &observerValue) == .success,
              let observer = observerValue else { return }
        
        observers[pid] = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        
        _ = AXObserverAddNotification(
            observer,
            appElement,
            kAXWindowCreatedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        registerCurrentWindows(pid: pid, appElement: appElement, observer: observer)
    }
    
    private func handleAccessibilityNotification(notification: String, pid: pid_t) {
        if notification == (kAXWindowCreatedNotification as String) {
            let appElement = AXUIElementCreateApplication(pid)
            if let observer = observers[pid] {
                registerCurrentWindows(pid: pid, appElement: appElement, observer: observer)
            }
        } else if notification == (kAXUIElementDestroyedNotification as String) {
            // Defer one main-loop turn so the app can update its accessibility tree.
            DispatchQueue.main.async { [weak self] in
                self?.recheckApp(pid: pid)
            }
        }
    }
    
    private func registerCurrentWindows(pid: pid_t, appElement: AXUIElement, observer: AXObserver) {
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return
        }
        
        for window in windows {
            var subroleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue) == .success,
               (subroleValue as? String) == (kAXStandardWindowSubrole as String) {
                hadStandardWindow.insert(pid)
            }
            
            _ = AXObserverAddNotification(
                observer,
                window,
                kAXUIElementDestroyedNotification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }
    
    private func recheckApp(pid: pid_t) {
        guard UserDefaults.standard.bool(forKey: "enableAutoQuit"),
              hadStandardWindow.contains(pid),
              let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated else { return }
        
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return
        }
        
        let hasStandardWindows = windows.contains { window in
            var subroleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                kAXSubroleAttribute as CFString,
                &subroleValue
            ) == .success else {
                // Unknown window types should not be treated as proof that no windows remain.
                return true
            }
            return (subroleValue as? String) == (kAXStandardWindowSubrole as String)
        }
        
        if !hasStandardWindows {
            hadStandardWindow.remove(pid)
            _ = app.terminate()
        }
    }
    
    private func removeObserver(for pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        hadStandardWindow.remove(pid)
    }
}
