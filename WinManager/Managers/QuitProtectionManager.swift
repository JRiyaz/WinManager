//
//  QuitProtectionManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import CoreGraphics
import os

final class QuitProtectionManager {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "QuitProtection")
    private var holdTimer: Timer?
    private var isHoldingCommandQ = false
    
    func handleKeyEvent(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        guard UserDefaults.standard.bool(forKey: "enableQuitProtection") else { return event }
        guard event.getIntegerValueField(.eventSourceUserData) != EventTapController.syntheticEventTag else {
            return event
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let commandIsDown = event.flags.contains(.maskCommand)
        
        guard keyCode == 12 else { return event } // Q key
        
        if type == .keyDown, commandIsDown {
            if !isHoldingCommandQ {
                isHoldingCommandQ = true
                holdTimer?.invalidate()
                logger.debug("⌘Q pressed; waiting for a one-second hold")
                holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                    guard let self, self.isHoldingCommandQ else { return }
                    self.postSyntheticQuit()
                    self.cancelPendingAction()
                }
            }
            // Swallow both the initial key-down and key repeat events.
            return nil
        }
        
        if type == .keyUp, isHoldingCommandQ {
            cancelPendingAction()
            return nil
        }
        
        return event
    }
    
    func handleFlagsChanged(_ event: CGEvent) {
        if isHoldingCommandQ, !event.flags.contains(.maskCommand) {
            logger.debug("Command released before hold duration; cancelling ⌘Q")
            cancelPendingAction()
        }
    }
    
    func cancelPendingAction() {
        isHoldingCommandQ = false
        holdTimer?.invalidate()
        holdTimer = nil
    }
    
    private func postSyntheticQuit() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        postKey(keyCode: 12, down: true, flags: .maskCommand, source: source)
        postKey(keyCode: 12, down: false, flags: .maskCommand, source: source)
        logger.info("⌘Q hold completed; posted a tagged quit shortcut")
    }
    
    private func postKey(keyCode: CGKeyCode, down: Bool, flags: CGEventFlags, source: CGEventSource) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticEventTag)
        event.post(tap: .cgSessionEventTap)
    }
}
