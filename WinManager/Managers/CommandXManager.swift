//
//  CommandXManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import CoreGraphics
import os

final class CommandXManager {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "CommandX")
    private var fileIsCut = false
    
    func handleKeyEvent(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        guard type == .keyDown,
              UserDefaults.standard.bool(forKey: "enableCommandX"),
              event.getIntegerValueField(.eventSourceUserData) != EventTapController.syntheticEventTag else {
            return event
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let commandIsDown = event.flags.contains(.maskCommand)
        
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            if fileIsCut { resetCutState() }
            return event
        }
        
        if keyCode == 53 { // Escape cancels the pending cut state.
            resetCutState()
            return event
        }
        
        if keyCode == 8, commandIsDown { // ⌘C cancels the pending cut state.
            resetCutState()
            return event
        }
        
        if keyCode == 7, commandIsDown { // ⌘X: copy first, then treat next ⌘V as move.
            guard postSyntheticKey(keyCode: 8, flags: .maskCommand) else { return event }
            fileIsCut = true
            logger.debug("Finder ⌘X translated to copy; waiting for paste")
            return nil
        }
        
        if keyCode == 9, commandIsDown, fileIsCut { // ⌘V
            let pasteboard = NSPasteboard.general
            let containsFileURL = pasteboard.canReadItem(
                withDataConformingToTypes: [NSPasteboard.PasteboardType.fileURL.rawValue]
            )
            
            guard containsFileURL else {
                resetCutState()
                return event
            }
            
            guard postSyntheticKey(keyCode: 9, flags: [.maskCommand, .maskAlternate]) else {
                resetCutState()
                return event
            }
            resetCutState()
            logger.debug("Finder ⌘V translated to ⌘⌥V (move)")
            return nil
        }
        
        return event
    }
    
    func resetCutState() {
        fileIsCut = false
    }
    
    private func postSyntheticKey(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            logger.error("Could not create synthetic Finder keyboard events")
            return false
        }
        
        for event in [keyDown, keyUp] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticEventTag)
        }
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }
}
