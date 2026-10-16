//
//  QuitProtectionManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit

final class QuitProtectionManager {
    private var holdTimer: Timer?
    private var isHolding = false

    func handleEvent(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        guard UserDefaults.standard.bool(forKey: "enableQuitProtection") else { return event }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        if keyCode == 12, flags.contains(.maskCommand) {
            if type == .keyDown {
                if !isHolding {
                    isHolding = true
                    DispatchQueue.main.async {
                        self.holdTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                            let quitEvent = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)
                            quitEvent?.flags = .maskCommand
                            quitEvent?.post(tap: .cgSessionEventTap)
                        }
                    }
                }
                return nil // Swallow the initial press
            } else if type == .keyUp {
                isHolding = false
                holdTimer?.invalidate()
                holdTimer = nil
            }
        }
        return event
    }
}
