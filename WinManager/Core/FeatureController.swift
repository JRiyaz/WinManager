//
//  FeatureController.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit

enum Feature: String {
    case switcher
    case scrollReverse
    case dockMinimize
    case autoQuit
}

final class FeatureController {
    private let eventTapController = EventTapController()
    private let scrollManager = ScrollManager()
    private let switcherManager = SwitcherManager()
    private let dockManager = DockManager()
    private let windowCloseManager = WindowCloseManager()

    func start() {
        eventTapController.onScroll = { [weak self] event in
            self?.scrollManager.transform(event) ?? event
        }
        eventTapController.onHotkey = { [weak self] reverse in
            guard UserDefaults.standard.bool(forKey: "enableAltTab") else { return false }
            self?.switcherManager.handleSwitchHotkey(reverse: reverse)
            return true
        }
        eventTapController.onModifierReleased = { [weak self] in
            self?.switcherManager.executeSwitch()
        }
        eventTapController.onMouseDown = { [weak self] event in
            guard UserDefaults.standard.bool(forKey: "enableDockClick") else { return false }
            return self?.dockManager.handleMouseDown(event) ?? false
        }
        eventTapController.start()
        windowCloseManager.start()
    }

    func stop() {
        eventTapController.stop()
        windowCloseManager.stop()
        switcherManager.dismiss()
    }

    func setEnabled(_ enabled: Bool, for feature: Feature) {
        switch feature {
        case .switcher:
            if !enabled { switcherManager.dismiss() }
        case .scrollReverse, .dockMinimize, .autoQuit:
            break
        }
    }
}
