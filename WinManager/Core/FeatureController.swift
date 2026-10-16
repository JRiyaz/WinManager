//
//  FeatureController.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import Combine

final class FeatureController {
    private let eventTapController = EventTapController()
    
    // UI-based Managers
    private let switcherManager = SwitcherManager()
    private let dockManager = DockManager()
    private let windowCloseManager = WindowCloseManager()
    
    // Background Utilities (Separated into files)
    private let scrollReverseManager = ScrollReverseManager()
    private let quitProtectionManager = QuitProtectionManager()
    private let commandXManager = CommandXManager()
    
    private var cancellables = Set<AnyCancellable>()

    init() {
        eventTapController.onScroll = { [weak self] event in
            return self?.scrollReverseManager.handleEvent(event) ?? event
        }
        
        eventTapController.onKeyDown = { [weak self] event, type in
            guard let self = self else { return event }
            var modified = event
            
            // Route through Quit Protection
            if let e = self.quitProtectionManager.handleEvent(modified, type: type) { modified = e } else { return nil }
            // Route through Command X
            if let e = self.commandXManager.handleEvent(modified, type: type) { modified = e } else { return nil }
            
            return modified
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
