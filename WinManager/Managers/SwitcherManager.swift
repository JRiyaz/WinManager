//
//  SwitcherManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import SwiftUI

struct SwitcherItem: Identifiable {
    let id: pid_t
    let app: NSRunningApplication
    var name: String { app.localizedName ?? app.bundleIdentifier ?? "Unknown App" }
    var icon: NSImage { app.icon ?? NSImage(size: NSSize(width: 32, height: 32)) }
}

final class SwitcherManager {
    private var panel: NSPanel?
    private var items: [SwitcherItem] = []
    private var selectedIndex = 0
    private var isShowing = false

    func handleSwitchHotkey(reverse: Bool) {
        refreshItems()
        guard !items.isEmpty else { return }

        if !isShowing {
            isShowing = true
            selectedIndex = initialIndex()
            showPanel()
        } else {
            selectedIndex = (selectedIndex + (reverse ? items.count - 1 : 1)) % items.count
            updatePanel()
        }
    }
    
    func executeSwitch() {
        guard isShowing, !items.isEmpty else { return }
        let selectedApp = items[selectedIndex].app
        
        // Bypasses the broken AXUIElement un-minimize and forces macOS to launch/focus the app natively
        if let url = selectedApp.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        }
        
        dismiss()
    }

    func dismiss() {
        panel?.orderOut(nil)
        isShowing = false
    }

    private func refreshItems() {
        items = NSWorkspace.shared.runningApplications
            .filter {
                !$0.isTerminated &&
                $0.activationPolicy == .regular &&
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
            .sorted {
                ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending
            }
            .map { SwitcherItem(id: $0.processIdentifier, app: $0) }
    }

    private func initialIndex() -> Int {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let index = items.firstIndex(where: { $0.id == frontmost.processIdentifier }) else { return 0 }
        return (index + 1) % items.count
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
        guard let panel else { showPanel(); return }
        panel.contentView = NSHostingView(rootView: AltTabOverlayView(items: items, selectedIndex: selectedIndex))
    }
}
