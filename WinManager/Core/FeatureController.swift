//
//  FeatureController.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import Combine
import os

final class FeatureController {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "FeatureController")
    private let eventTapController = EventTapController()

    // UI-based Managers
    private let switcherManager = SwitcherManager()
    private let dockManager = DockManager()
    private let windowCloseManager = WindowCloseManager()

    // Background Utilities
    private let scrollReverseManager = ScrollReverseManager()
    private let quitProtectionManager = QuitProtectionManager()
    private let commandXManager = CommandXManager()

    private var cancellables = Set<AnyCancellable>()

    init() {
        eventTapController.onScroll = { [weak self] event in
            return self?.scrollReverseManager.handleEvent(event) ?? event
        }

        eventTapController.onKeyEvent = { [weak self] event, type in
            guard let self = self else { return event }
            var current: CGEvent? = event

            // 1. Route through Quit Protection
            if let e = current {
                current = self.quitProtectionManager.handleKeyEvent(e, type: type)
            }

            // 2. Route through Command X
            if let e = current {
                current = self.commandXManager.handleKeyEvent(e, type: type)
            }

            return current
        }

        eventTapController.onFlagsChanged = { [weak self] event in
            self?.quitProtectionManager.handleFlagsChanged(event)
        }

        eventTapController.onHotkey = { [weak self] reverse in
            self?.switcherManager.handleSwitchHotkey(reverse: reverse)
            return true
        }

        eventTapController.onModifierReleased = { [weak self] in
            self?.switcherManager.executeSwitch()
        }

        eventTapController.onMouseDown = { [weak self] event in
            return self?.dockManager.handleMouseDown(event) ?? false
        }

        // Reset Finder cut state when active application changes
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != "com.apple.finder" {
                self?.commandXManager.resetCutState()
            }
        }

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.evaluateState() }
            .store(in: &cancellables)
    }

    func start() {
        UserDefaults.standard.register(defaults: [
            "enableAppSwitcher": false,
            "enableScrollReverse": true,
            "enableDockClicks": true,
            "enableAutoQuit": true,
            "enableQuitProtection": true,
            "enableCommandX": true
        ])

        eventTapController.start()
        evaluateState()
    }

    func refreshPermissions() {
        logger.info("Refreshing permissions and retrying event tap...")
        if PermissionsManager.hasInputMonitoring && !eventTapController.isActive {
            eventTapController.start()
        }
        evaluateState()
    }

    func stop() {
        eventTapController.stop()
        windowCloseManager.stop()
        switcherManager.dismiss()
    }

    private func evaluateState() {
        if UserDefaults.standard.bool(forKey: "enableAutoQuit") {
            windowCloseManager.start()
        } else {
            windowCloseManager.stop()
        }

        if !UserDefaults.standard.bool(forKey: "enableAppSwitcher") {
            switcherManager.dismiss()
        }
    }
}

