//
//  EventTapController.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices
import CoreGraphics
import os

final class EventTapController {
    static let syntheticEventTag: Int64 = 0x57494E4D // "WINM"
    
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "EventTap")
    
    var onScroll: ((CGEvent) -> CGEvent?)?
    var onKeyEvent: ((CGEvent, CGEventType) -> CGEvent?)?
    var onFlagsChanged: ((CGEvent) -> Void)?
    var onHotkey: ((Bool) -> Bool)?
    var onModifierReleased: (() -> Void)?
    var onMouseDown: ((CGEvent) -> Bool)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cleaningModeEnabled = false
    private var commandModifierWasDown = false
    private var suppressNextLeftMouseUp = false
    
    // Keys whose key-down was delivered to the foreground app. On entering
    // Cleaning Mode, matching releases are still delivered to avoid stuck keys.
    private var deliveredKeyCodes = Set<Int64>()
    private var deliveredModifierKeyCodes = Set<Int64>()
    private var keysHeldAtCleaningStart = Set<Int64>()
    private var modifiersHeldAtCleaningStart = Set<Int64>()
    
    // Presses suppressed during Cleaning Mode remain suppressed through their
    // physical release, even if the 60-second timeout ends the mode first.
    private var cleaningSuppressedKeyCodes = Set<Int64>()
    private var pendingSuppressedKeyUps = Set<Int64>()
    private var cleaningSuppressedModifierKeyCodes = Set<Int64>()
    private var pendingSuppressedModifierReleases = Set<Int64>()
    private var suppressedUntilKeyUp = Set<Int64>()
    
    var isActive: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }
    
    func start() {
        guard eventTap == nil else {
            if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        
        guard PermissionsManager.hasInputMonitoring else {
            logger.warning("Event tap not started: Input Monitoring permission is missing")
            return
        }
        
        let mask = (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
        | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
        | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
            
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                controller.logger.notice("Event tap disabled by system; re-enabling it")
                if let eventTap = controller.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            
            return controller.process(event: event, type: type)
        }
        
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            logger.error("Unable to create event tap. Check Input Monitoring in System Settings.")
            return
        }
        
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            logger.error("Unable to create event-tap run-loop source")
            return
        }
        
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Event tap started")
    }
    
    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        
        runLoopSource = nil
        eventTap = nil
        cleaningModeEnabled = false
        commandModifierWasDown = false
        suppressNextLeftMouseUp = false
        deliveredKeyCodes.removeAll(keepingCapacity: false)
        deliveredModifierKeyCodes.removeAll(keepingCapacity: false)
        keysHeldAtCleaningStart.removeAll(keepingCapacity: false)
        modifiersHeldAtCleaningStart.removeAll(keepingCapacity: false)
        cleaningSuppressedKeyCodes.removeAll(keepingCapacity: false)
        pendingSuppressedKeyUps.removeAll(keepingCapacity: false)
        cleaningSuppressedModifierKeyCodes.removeAll(keepingCapacity: false)
        pendingSuppressedModifierReleases.removeAll(keepingCapacity: false)
        suppressedUntilKeyUp.removeAll(keepingCapacity: false)
        logger.info("Event tap stopped")
    }
    
    func setCleaningMode(_ enabled: Bool) {
        guard enabled != cleaningModeEnabled else { return }
        
        if enabled {
            keysHeldAtCleaningStart = deliveredKeyCodes
            modifiersHeldAtCleaningStart = deliveredModifierKeyCodes
            cleaningSuppressedKeyCodes.removeAll(keepingCapacity: true)
            cleaningSuppressedModifierKeyCodes.removeAll(keepingCapacity: true)
            cleaningModeEnabled = true
            logger.info("Cleaning Mode input filter enabled")
        } else {
            pendingSuppressedKeyUps.formUnion(cleaningSuppressedKeyCodes)
            pendingSuppressedModifierReleases.formUnion(cleaningSuppressedModifierKeyCodes)
            cleaningSuppressedKeyCodes.removeAll(keepingCapacity: true)
            cleaningSuppressedModifierKeyCodes.removeAll(keepingCapacity: true)
            keysHeldAtCleaningStart.removeAll(keepingCapacity: true)
            modifiersHeldAtCleaningStart.removeAll(keepingCapacity: true)
            cleaningModeEnabled = false
            logger.info("Cleaning Mode input filter disabled")
        }
    }
    
    private func process(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        // Cleaning Mode is checked before the synthetic-event bypass so pending
        // generated keystrokes cannot leak into another app while the lock is on.
        if cleaningModeEnabled {
            return processCleaningMode(event: event, type: type)
        }
        
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }
        
        switch type {
        case .scrollWheel:
            let changed = onScroll?(event) ?? event
            return Unmanaged.passUnretained(changed)
            
        case .leftMouseDown:
            // Clear a stale suppression marker if a prior mouse-up was not observed.
            suppressNextLeftMouseUp = false
            if UserDefaults.standard.bool(forKey: "enableDockClicks"),
               onMouseDown?(event) == true {
                suppressNextLeftMouseUp = true
                return nil
            }
            return Unmanaged.passUnretained(event)
            
        case .leftMouseUp:
            if suppressNextLeftMouseUp {
                suppressNextLeftMouseUp = false
                return nil
            }
            return Unmanaged.passUnretained(event)
            
        case .keyDown:
            return processKeyDown(event)
            
        case .keyUp:
            return processKeyUp(event)
            
        case .flagsChanged:
            return processFlagsChanged(event)
            
        default:
            return Unmanaged.passUnretained(event)
        }
    }
    
    private func processKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let managerResult: CGEvent?
        if let onKeyEvent {
            managerResult = onKeyEvent(event, .keyDown)
        } else {
            managerResult = event
        }
        guard let eventAfterManagers = managerResult else {
            suppressedUntilKeyUp.insert(keyCode)
            return nil
        }
        
        let flags = eventAfterManagers.flags
        if keyCode == 48, flags.contains(.maskCommand) {
            let reverse = flags.contains(.maskShift)
            if UserDefaults.standard.bool(forKey: "enableAppSwitcher"), onHotkey?(reverse) == true {
                suppressedUntilKeyUp.insert(keyCode)
                return nil
            }
        }
        
        deliveredKeyCodes.insert(keyCode)
        return Unmanaged.passUnretained(eventAfterManagers)
    }
    
    private func processKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let managerResult: CGEvent?
        if let onKeyEvent {
            managerResult = onKeyEvent(event, .keyUp)
        } else {
            managerResult = event
        }
        
        deliveredKeyCodes.remove(keyCode)
        if suppressedUntilKeyUp.remove(keyCode) != nil {
            return nil
        }
        if pendingSuppressedKeyUps.remove(keyCode) != nil {
            return nil
        }
        guard let eventAfterManagers = managerResult else { return nil }
        return Unmanaged.passUnretained(eventAfterManagers)
    }
    
    private func processFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        if pendingSuppressedModifierReleases.contains(keyCode),
           let flag = modifierFlag(for: keyCode),
           !event.flags.contains(flag) {
            pendingSuppressedModifierReleases.remove(keyCode)
            deliveredModifierKeyCodes.remove(keyCode)
            return nil
        }
        
        onFlagsChanged?(event)
        let commandIsDown = event.flags.contains(.maskCommand)
        if commandModifierWasDown && !commandIsDown {
            onModifierReleased?()
        }
        commandModifierWasDown = commandIsDown
        updateModifierTracking(keyCode: keyCode, flags: event.flags)
        return Unmanaged.passUnretained(event)
    }
    
    private func processCleaningMode(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        switch type {
        case .keyDown:
            // A key already down before activation may repeat; never deliver repeats.
            if !keysHeldAtCleaningStart.contains(keyCode) {
                cleaningSuppressedKeyCodes.insert(keyCode)
            }
            return nil
            
        case .keyUp:
            deliveredKeyCodes.remove(keyCode)
            pendingSuppressedKeyUps.remove(keyCode)
            if keysHeldAtCleaningStart.remove(keyCode) != nil {
                // Balance a key-down delivered before Cleaning Mode was enabled.
                return Unmanaged.passUnretained(event)
            }
            cleaningSuppressedKeyCodes.remove(keyCode)
            suppressedUntilKeyUp.remove(keyCode)
            return nil
            
        case .flagsChanged:
            commandModifierWasDown = event.flags.contains(.maskCommand)
            if pendingSuppressedModifierReleases.contains(keyCode),
               let pendingFlag = modifierFlag(for: keyCode),
               !event.flags.contains(pendingFlag) {
                pendingSuppressedModifierReleases.remove(keyCode)
                return nil
            }
            // Caps Lock is a toggle rather than a conventional held modifier.
            if keyCode == 57 { return nil }
            
            if modifiersHeldAtCleaningStart.contains(keyCode),
               let flag = modifierFlag(for: keyCode),
               !event.flags.contains(flag) {
                modifiersHeldAtCleaningStart.remove(keyCode)
                deliveredModifierKeyCodes.remove(keyCode)
                return Unmanaged.passUnretained(event)
            }
            
            // Modifier changes are normally swallowed. Toggle tracking handles
            // both press/release events and lets us suppress a later release if
            // Cleaning Mode ends while a modifier is physically still held.
            if cleaningSuppressedModifierKeyCodes.contains(keyCode) {
                cleaningSuppressedModifierKeyCodes.remove(keyCode)
            } else {
                cleaningSuppressedModifierKeyCodes.insert(keyCode)
            }
            return nil
            
        default:
            // Only keyboard events are masked in Cleaning Mode; mouse and scroll
            // remain usable so the user can clean the keyboard and exit the mode.
            return Unmanaged.passUnretained(event)
        }
    }
    
    private func modifierFlag(for keyCode: Int64) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 57: return .maskAlphaShift
        case 63: return .maskSecondaryFn
        default: return nil
        }
    }
    
    private func updateModifierTracking(keyCode: Int64, flags: CGEventFlags) {
        guard let flag = modifierFlag(for: keyCode) else { return }
        if flags.contains(flag) {
            deliveredModifierKeyCodes.insert(keyCode)
        } else {
            deliveredModifierKeyCodes.remove(keyCode)
        }
    }
}
