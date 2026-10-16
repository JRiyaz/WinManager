//
//  SwitcherManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import SwiftUI
import os

struct SwitcherItem: Identifiable {
    let id: pid_t
    let app: NSRunningApplication
    var name: String { app.localizedName ?? app.bundleIdentifier ?? "Unknown App" }
    var icon: NSImage { app.icon ?? NSImage(size: NSSize(width: 32, height: 32)) }
}

final class SwitcherManager {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "Switcher")

    private var panel: NSPanel?
    private var items: [SwitcherItem] = []
    private var selectedIndex = 0
    private var isShowing = false

    // Most-Recently-Used (MRU) tracking for running applications
    private var mruPids: [pid_t] = []

    init() {
        // Track application activation to maintain accurate MRU order
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.recordAppActivation(notification)
        }

        // Initialize MRU with current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            mruPids.append(frontmost.processIdentifier)
        }
    }

    func recordAppActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        let pid = app.processIdentifier
        mruPids.removeAll { $0 == pid }
        mruPids.insert(pid, at: 0)
    }

    func handleSwitchHotkey(reverse: Bool) {
        if !isShowing {
            refreshItems()
            guard !items.isEmpty else { return }

            isShowing = true
            // Default to index 1 (the previously active app in MRU order)
            selectedIndex = items.count > 1 ? 1 : 0
            showPanel()
        } else {
            guard !items.isEmpty else { return }
            selectedIndex = (selectedIndex + (reverse ? items.count - 1 : 1)) % items.count
            updatePanel()
        }
    }

    func executeSwitch() {
        guard isShowing, !items.isEmpty else {
            dismiss()
            return
        }

        let selectedApp = items[selectedIndex].app
        dismiss()

        guard !selectedApp.isTerminated else { return }

        // 1. Unhide if the application is currently hidden
        if selectedApp.isHidden {
            selectedApp.unhide()
        }

        // 2. Activate existing running instance natively
        let activated = selectedApp.activate(options: [.activateIgnoringOtherApps])
        logger.info("Activated \(selectedApp.localizedName ?? "app"): \(activated)")

        // 3. If standard windows are minimized, un-minimize them via Accessibility
        if PermissionsManager.hasAccessibility {
            let appElement = AXUIElementCreateApplication(selectedApp.processIdentifier)
            var windowsValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
               let windows = windowsValue as? [AXUIElement] {
                for window in windows {
                    var isMinimized: CFTypeRef?
                    if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &isMinimized) == .success,
                       let minVal = isMinimized as? Bool, minVal == true {
                        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                        break
                    }
                }
            }
        }

        // Update MRU with newly selected application
        mruPids.removeAll { $0 == selectedApp.processIdentifier }
        mruPids.insert(selectedApp.processIdentifier, at: 0)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        isShowing = false
    }

    private func refreshItems() {
        let running = NSWorkspace.shared.runningApplications
            .filter {
                !$0.isTerminated &&
                $0.activationPolicy == .regular &&
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }

        // Sort by MRU order: apps that were active recently appear first
        items = running.sorted { appA, appB in
            let indexA = mruPids.firstIndex(of: appA.processIdentifier) ?? Int.max
            let indexB = mruPids.firstIndex(of: appB.processIdentifier) ?? Int.max
            if indexA != indexB {
                return indexA < indexB
            }
            return (appA.localizedName ?? "").localizedCaseInsensitiveCompare(appB.localizedName ?? "") == .orderedAscending
        }
        .map { SwitcherItem(id: $0.processIdentifier, app: $0) }
    }

    private func showPanel() {
        let view = AltTabOverlayView(items: items, selectedIndex: selectedIndex)
        let hosting = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
                y: screen.visibleFrame.midY - panel.frame.height / 2
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func updatePanel() {
        guard let panel else {
            showPanel()
            return
        }
        panel.contentView = NSHostingView(rootView: AltTabOverlayView(items: items, selectedIndex: selectedIndex))
    }
}

