//
//  CommandXManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit

final class CommandXManager {
    private var fileIsCut = false

    func handleEvent(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        guard type == .keyDown, UserDefaults.standard.bool(forKey: "enableCommandX") else { return event }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == "com.apple.finder" else {
            return event
        }
        
        // ⌘X (Keycode 7)
        if keyCode == 7, flags.contains(.maskCommand) {
            fileIsCut = true
            
            // Post a clean ⌘C without the "X" string payload
            let copyDown = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true)
            copyDown?.flags = .maskCommand
            copyDown?.post(tap: .cgSessionEventTap)
            
            let copyUp = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false)
            copyUp?.flags = .maskCommand
            copyUp?.post(tap: .cgSessionEventTap)
            
            return nil // Swallow original ⌘X to prevent the error beep
        }
        
        // ⌘V (Keycode 9)
        if keyCode == 9, flags.contains(.maskCommand) {
            if fileIsCut {
                fileIsCut = false
                
                // Post a clean ⌘⌥V
                let moveDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
                moveDown?.flags = [.maskCommand, .maskAlternate]
                moveDown?.post(tap: .cgSessionEventTap)
                
                let moveUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
                moveUp?.flags = [.maskCommand, .maskAlternate]
                moveUp?.post(tap: .cgSessionEventTap)
                
                return nil // Swallow original ⌘V
            }
        }
        
        if keyCode == 53 { fileIsCut = false } // Cancel on Escape
        
        return event
    }
}
