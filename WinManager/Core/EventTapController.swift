//
//  EventTapController.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices

/// Owns one session-level event tap. Keep callback work minimal.
final class EventTapController {
    var onScroll: ((CGEvent) -> CGEvent?)?
    /// Return true to consume the system event. `reverse` is true for Cmd+Shift+Tab.
    var onHotkey: ((Bool) -> Bool)?
    /// Triggered when the Command modifier is released.
    var onModifierReleased: (() -> Void)?
    /// Return true to consume a left mouse-down event.
    var onMouseDown: ((CGEvent) -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()

    func start() {
        guard eventTap == nil else { return }
        guard PermissionsManager.hasInputMonitoring else {
            _ = PermissionsManager.requestInputMonitoringPrompt()
            return
        }

        let mask = (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                controller.reenableTap()
                return Unmanaged.passUnretained(event)
            }

            switch type {
            case .scrollWheel:
                guard UserDefaults.standard.bool(forKey: "enableScrollReverse"),
                      let changed = controller.onScroll?(event) else {
                    return Unmanaged.passUnretained(event)
                }
                return Unmanaged.passUnretained(changed)

            case .leftMouseDown:
                if UserDefaults.standard.bool(forKey: "enableDockClick"),
                   controller.onMouseDown?(event) == true {
                    return nil
                }
                return Unmanaged.passUnretained(event)

            case .keyDown:
                // keyCode 48 is Tab. Command modifier is required.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                if keyCode == 48, flags.contains(.maskCommand) {
                    let reverse = flags.contains(.maskShift)
                    if UserDefaults.standard.bool(forKey: "enableAltTab"),
                       controller.onHotkey?(reverse) == true {
                        return nil
                    }
                }
                return Unmanaged.passUnretained(event)

            case .flagsChanged:
                let flags = event.flags
                if !flags.contains(.maskCommand) {
                    controller.onModifierReleased?()
                }
                return Unmanaged.passUnretained(event)

            default:
                return Unmanaged.passUnretained(event)
            }
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
            // This will tell us if macOS is still killing the request
            print("🚨 FATAL: Event Tap blocked. macOS refused permission or Sandbox is still active.")
            return
        }
        print("✅ Event Tap successfully created and active!")
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
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
    }

    fileprivate func reenableTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
}
