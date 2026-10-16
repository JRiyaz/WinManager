//
//  SwitcherManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices
import SwiftUI
import os

struct SwitcherItem: Identifiable {
    let id: pid_t
    let app: NSRunningApplication
    var name: String { app.localizedName ?? app.bundleIdentifier ?? "Unknown App" }
    var icon: NSImage { app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: name) ?? NSImage(size: NSSize(width: 48, height: 48)) }
}

final class SwitcherManager {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "Switcher")
    
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AltTabOverlayView>?
    private var items: [SwitcherItem] = []
    private var selectedIndex = 0
    private var isShowing = false
    private var mruPIDs: [pid_t] = []
    private var activationObserver: NSObjectProtocol?
    
    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.recordActivation(app)
        }
        
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            mruPIDs = [frontmost.processIdentifier]
        }
    }
    
    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }
    
    @discardableResult
    func handleSwitchHotkey(reverse: Bool) -> Bool {
        guard UserDefaults.standard.bool(forKey: "enableAppSwitcher") else { return false }
        
        if !isShowing {
            refreshItems()
            guard items.count > 1 else { return false }
            
            isShowing = true
            if reverse {
                selectedIndex = items.count - 1
            } else {
                selectedIndex = items.count > 1 ? 1 : 0
            }
            showPanel()
            return panel != nil
        }
        
        guard !items.isEmpty else {
            dismiss()
            return false
        }
        
        selectedIndex = (selectedIndex + (reverse ? items.count - 1 : 1)) % items.count
        updatePanel()
        return true
    }
    
    func executeSwitch() {
        guard isShowing, items.indices.contains(selectedIndex) else {
            dismiss()
            return
        }
        
        let app = items[selectedIndex].app
        dismiss()
        guard !app.isTerminated else { return }
        
        if app.isHidden {
            app.unhide()
        }
        
        // Best effort: restore a minimized standard window before activating.
        if PermissionsManager.hasAccessibility {
            restoreOneMinimizedWindow(processIdentifier: app.processIdentifier)
        }
        
        let sourceApp = NSWorkspace.shared.frontmostApplication
        
        let activated: Bool
        if let sourceApp,
           sourceApp.processIdentifier != app.processIdentifier {
            activated = app.activate(from: sourceApp, options: [])
        } else {
            activated = app.activate(options: [])
        }
        logger.info("Activation requested for \(app.localizedName ?? "app"): \(activated)")
        recordActivation(app)
    }
    
    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        isShowing = false
        items.removeAll(keepingCapacity: true)
    }
    
    private func recordActivation(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular,
              !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = app.processIdentifier
        mruPIDs.removeAll { $0 == pid }
        mruPIDs.insert(pid, at: 0)
    }
    
    private func refreshItems() {
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated &&
            $0.activationPolicy == .regular &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        
        // Preserve the observed MRU order. Applications without an activation
        // observation are appended deterministically by name.
        items = running.sorted { lhs, rhs in
            let lhsIndex = mruPIDs.firstIndex(of: lhs.processIdentifier) ?? Int.max
            let rhsIndex = mruPIDs.firstIndex(of: rhs.processIdentifier) ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return (lhs.localizedName ?? "").localizedCaseInsensitiveCompare(rhs.localizedName ?? "") == .orderedAscending
        }.map { SwitcherItem(id: $0.processIdentifier, app: $0) }
    }
    
    private func showPanel() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            isShowing = false
            return
        }
        
        let panelWidth = min(max(CGFloat(items.count) * 150 + 24, 480), max(480, screen.visibleFrame.width - 40))
        let contentView = AltTabOverlayView(items: items, selectedIndex: selectedIndex)
        let hosting = NSHostingView(rootView: contentView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 178),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        panel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - panel.frame.width / 2,
            y: screen.visibleFrame.midY - panel.frame.height / 2
        ))
        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hosting
    }
    
    private func updatePanel() {
        guard let hostingView else {
            showPanel()
            return
        }
        hostingView.rootView = AltTabOverlayView(items: items, selectedIndex: selectedIndex)
    }
    
    private func restoreOneMinimizedWindow(processIdentifier pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
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
            var minimizedValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                &minimizedValue
            ) == .success,
                  (minimizedValue as? Bool) == true else {
                continue
            }
            
            _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            break
        }
    }
}
