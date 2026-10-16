//
//  FeatureController.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import os

final class FeatureController {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "FeatureController")
    
    private let eventTapController = EventTapController()
    private let switcherManager = SwitcherManager()
    private let dockManager = DockManager()
    private let windowCloseManager = WindowCloseManager()
    private let scrollReverseManager = ScrollReverseManager()
    private let quitProtectionManager = QuitProtectionManager()
    private let commandXManager = CommandXManager()
    
    private var cleaningModeTimeout: DispatchWorkItem?
    private var finderActivationObserver: NSObjectProtocol?
    private var hasStarted = false
    
    var isInputTapActive: Bool { eventTapController.isActive }
    
    init() {
        eventTapController.onScroll = { [weak self] event in
            self?.scrollReverseManager.handleEvent(event) ?? event
        }
        
        eventTapController.onKeyEvent = { [weak self] event, type in
            guard let self else { return event }
            var current: CGEvent? = event
            if let value = current {
                current = self.quitProtectionManager.handleKeyEvent(value, type: type)
            }
            if let value = current {
                current = self.commandXManager.handleKeyEvent(value, type: type)
            }
            return current
        }
        
        eventTapController.onFlagsChanged = { [weak self] event in
            self?.quitProtectionManager.handleFlagsChanged(event)
        }
        
        eventTapController.onHotkey = { [weak self] reverse in
            self?.switcherManager.handleSwitchHotkey(reverse: reverse) ?? false
        }
        
        eventTapController.onModifierReleased = { [weak self] in
            self?.switcherManager.executeSwitch()
        }
        
        eventTapController.onMouseDown = { [weak self] event in
            guard UserDefaults.standard.bool(forKey: "enableDockClicks") else { return false }
            return self?.dockManager.handleMouseDown(event) ?? false
        }
        
        finderActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            if app.bundleIdentifier != "com.apple.finder" {
                self?.commandXManager.resetCutState()
            }
        }
    }
    
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        
        UserDefaults.standard.register(defaults: [
            "enableAppSwitcher": false,
            "enableScrollReverse": true,
            "enableDockClicks": true,
            "enableAutoQuit": false,
            "enableQuitProtection": true,
            "enableCommandX": true,
            "enableCleaningMode": false
        ])
        
        // Cleaning Mode is intentionally never restored from persistent defaults.
        UserDefaults.standard.set(false, forKey: "enableCleaningMode")
        eventTapController.setCleaningMode(false)
        refreshPermissions()
        refreshFeatureState()
    }
    
    func refreshPermissions() {
        if PermissionsManager.hasInputMonitoring {
            eventTapController.start()
        } else {
            if UserDefaults.standard.bool(forKey: "enableCleaningMode") {
                disableCleaningMode()
            }
            eventTapController.stop()
        }
        refreshFeatureState()
    }
    
    func refreshFeatureState() {
        if UserDefaults.standard.bool(forKey: "enableAutoQuit"), PermissionsManager.hasAccessibility {
            windowCloseManager.start()
        } else {
            windowCloseManager.stop()
        }
        
        if !UserDefaults.standard.bool(forKey: "enableAppSwitcher") {
            switcherManager.dismiss()
        }
        
        if !UserDefaults.standard.bool(forKey: "enableQuitProtection") {
            quitProtectionManager.cancelPendingAction()
        }
        
        if !UserDefaults.standard.bool(forKey: "enableCommandX") {
            commandXManager.resetCutState()
        }
    }
    
    func enableCleaningMode() {
        guard PermissionsManager.hasInputMonitoring, eventTapController.isActive else {
            logger.warning("Cleaning Mode requested without an active Input Monitoring event tap")
            UserDefaults.standard.set(false, forKey: "enableCleaningMode")
            eventTapController.setCleaningMode(false)
            return
        }
        
        guard !UserDefaults.standard.bool(forKey: "enableCleaningMode") else { return }
        UserDefaults.standard.set(true, forKey: "enableCleaningMode")
        quitProtectionManager.cancelPendingAction()
        commandXManager.resetCutState()
        switcherManager.dismiss()
        eventTapController.setCleaningMode(true)
        
        let timeout = DispatchWorkItem { [weak self] in
            self?.disableCleaningMode()
        }
        cleaningModeTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: timeout)
        logger.info("Cleaning Mode enabled for up to 60 seconds")
    }
    
    func disableCleaningMode() {
        cleaningModeTimeout?.cancel()
        cleaningModeTimeout = nil
        eventTapController.setCleaningMode(false)
        UserDefaults.standard.set(false, forKey: "enableCleaningMode")
    }
    
    func stop() {
        cleaningModeTimeout?.cancel()
        cleaningModeTimeout = nil
        UserDefaults.standard.set(false, forKey: "enableCleaningMode")
        eventTapController.setCleaningMode(false)
        eventTapController.stop()
        windowCloseManager.stop()
        switcherManager.dismiss()
        
        if let finderActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(finderActivationObserver)
            self.finderActivationObserver = nil
        }
        hasStarted = false
    }
}
