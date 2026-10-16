//
//  WindowCloseManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices
import os

private final class WindowCloseObservation {
    let processIdentifier: pid_t
    let observer: AXObserver
    let appElement: AXUIElement
    var observedWindowHashes = Set<CFHashCode>()
    
    init(processIdentifier: pid_t, observer: AXObserver, appElement: AXUIElement) {
        self.processIdentifier = processIdentifier
        self.observer = observer
        self.appElement = appElement
    }
}

private func windowCloseObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let manager = Unmanaged<WindowCloseManager>.fromOpaque(refcon).takeUnretainedValue()
    manager.handleAXNotification(observer: observer, element: element, notification: notification as String)
}

/// Event-driven best-effort auto-quit. It listens for Accessibility window
/// notifications rather than polling every second. macOS apps can legitimately
/// remain running without windows; this behavior should therefore stay opt-in.
final class WindowCloseManager {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "WindowClose")
    
    private var observations: [pid_t: WindowCloseObservation] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var isStarted = false
    
    private let excludedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.ActivityMonitor",
        "com.apple.dt.Xcode",
        "com.apple.Terminal",
        "com.googlecode.iterm2"
    ]
    
    func start() {
        guard !isStarted, PermissionsManager.hasAccessibility else { return }
        isStarted = true
        
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attach(to: app)
        })
        
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.detach(processIdentifier: app.processIdentifier)
        })
        
        for app in NSWorkspace.shared.runningApplications {
            attach(to: app)
        }
        logger.info("Started event-driven last-window monitoring")
    }
    
    func stop() {
        guard isStarted || !observations.isEmpty || !workspaceTokens.isEmpty else { return }
        isStarted = false
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
        
        for pid in Array(observations.keys) {
            detach(processIdentifier: pid)
        }
        logger.info("Stopped last-window monitoring")
    }
    
    private func attach(to app: NSRunningApplication) {
        guard isStarted,
              PermissionsManager.hasAccessibility,
              !app.isTerminated,
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              observations[app.processIdentifier] == nil,
              let bundleID = app.bundleIdentifier,
              !excludedBundleIdentifiers.contains(bundleID) else {
            return
        }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        
        var observerValue: AXObserver?
        guard AXObserverCreate(pid, windowCloseObserverCallback, &observerValue) == .success,
              let observer = observerValue else {
            return
        }
        
        let observation = WindowCloseObservation(processIdentifier: pid, observer: observer, appElement: appElement)
        observations[pid] = observation
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(
            observer,
            appElement,
            kAXWindowCreatedNotification as CFString,
            context
        )
        observeExistingWindows(observation: observation, context: context)
    }
    
    private func observeExistingWindows(observation: WindowCloseObservation, context: UnsafeMutableRawPointer) {
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            observation.appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return
        }
        
        for window in windows {
            AXUIElementSetMessagingTimeout(window, 0.2)
            let windowHash = CFHash(window)
            guard observation.observedWindowHashes.insert(windowHash).inserted else { continue }
            _ = AXObserverAddNotification(
                observation.observer,
                window,
                kAXUIElementDestroyedNotification as CFString,
                context
            )
        }
    }
    
    private func detach(processIdentifier pid: pid_t) {
        guard let observation = observations.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observation.observer),
            .commonModes
        )
    }
    
    func handleAXNotification(observer: AXObserver, element: AXUIElement, notification: String) {
        // Resolve the PID by observer identity rather than messaging a UI element
        // that may already have been destroyed.
        guard let observation = observations.values.first(where: { CFEqual($0.observer, observer) }) else {
            return
        }
        let pid = observation.processIdentifier
        
        if notification == (kAXWindowCreatedNotification as String) {
            observeExistingWindows(
                observation: observation,
                context: Unmanaged.passUnretained(self).toOpaque()
            )
            return
        }
        
        guard notification == (kAXUIElementDestroyedNotification as String) else { return }
        observation.observedWindowHashes.remove(CFHash(element))
        
        // Run the query after the destruction notification has been dispatched.
        // No timer or periodic polling is used.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.terminateIfNoWindows(processIdentifier: pid)
        }
    }
    
    private func terminateIfNoWindows(processIdentifier pid: pid_t) {
        guard UserDefaults.standard.bool(forKey: "enableAutoQuit"),
              PermissionsManager.hasAccessibility,
              let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated,
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier,
              !excludedBundleIdentifiers.contains(bundleID) else {
            return
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            // A failed/unknown Accessibility query is never interpreted as zero windows.
            return
        }
        
        // Count all AX windows (not only standard windows). An empty successful
        // result is a stronger signal and avoids quitting when a utility/panel
        // window remains open.
        guard windows.isEmpty else { return }
        logger.notice("Last accessible window closed; requesting termination for \(app.localizedName ?? "application")")
        _ = app.terminate()
        detach(processIdentifier: pid)
    }
}
