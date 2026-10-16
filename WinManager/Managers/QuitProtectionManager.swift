//
//  QuitProtectionManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import os

final class QuitProtectionManager {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "QuitProtection")
    private var holdTimer: Timer?
    private var isHolding = false

    func handleKeyEvent(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        guard UserDefaults.standard.bool(forKey: "enableQuitProtection") else { return event }

        // Ignore our own synthetic quit events
        if event.getIntegerValueField(.eventSourceUserData) == EventTapController.syntheticEventTag {
            return event
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // ⌘Q (virtual key 12)
        if keyCode == 12, flags.contains(.maskCommand) {
            if type == .keyDown {
                // If this is a key-repeat event while already holding, just swallow it
                if isHolding {
                    return nil
                }

                isHolding = true
                logger.info("Cmd+Q pressed. Starting 1-second hold timer.")

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.holdTimer?.invalidate()
                    self.holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                        guard let self, self.isHolding else { return }
                        self.logger.notice("Cmd+Q held for 1.0s. Posting synthetic quit event.")
                        self.postSyntheticQuit()
                        self.cancelHold()
                    }
                }
                return nil // Swallow the initial key-down
            } else if type == .keyUp {
                if isHolding {
                    logger.info("Q key released before 1.0s. Cancelling quit.")
                    cancelHold()
                    return nil // Swallow keyUp since corresponding keyDown was swallowed
                }
            }
        }

        return event
    }

    func handleFlagsChanged(_ event: CGEvent) {
        // If the Command key modifier is released while holding Q, cancel the quit timer
        if isHolding, !event.flags.contains(.maskCommand) {
            logger.info("Command modifier released before 1.0s. Cancelling quit.")
            cancelHold()
        }
    }

    func cancelHold() {
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func postSyntheticQuit() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        if let quitDown = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: true) {
            quitDown.flags = .maskCommand
            quitDown.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticEventTag)
            quitDown.post(tap: .cgSessionEventTap)
        }

        if let quitUp = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: false) {
            quitUp.flags = .maskCommand
            quitUp.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticEventTag)
            quitUp.post(tap: .cgSessionEventTap)
        }
    }
}

