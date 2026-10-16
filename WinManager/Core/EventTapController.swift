//
//  EventTapController.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import ApplicationServices

final class EventTapController {
    var onScroll: ((CGEvent) -> CGEvent?)?
    var onKeyDown: ((CGEvent, CGEventType) -> CGEvent?)?
    var onHotkey: ((Bool) -> Bool)?
    var onModifierReleased: (() -> Void)?
    var onMouseDown: ((CGEvent) -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard eventTap == nil, PermissionsManager.hasInputMonitoring else { return }

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
                let modifiedEvent = controller.onScroll?(event) ?? event
                return Unmanaged.passUnretained(modifiedEvent)

            case .leftMouseDown:
                if UserDefaults.standard.bool(forKey: "enableDockClicks"),
                   controller.onMouseDown?(event) == true {
                    return nil
                }
                return Unmanaged.passUnretained(event)

            case .keyDown, .keyUp:
                var currentEvent: CGEvent? = event
                
                // 1. Route to background utilities (Cmd+X, Quit Protection)
                if let handler = controller.onKeyDown {
                    currentEvent = handler(currentEvent!, type)
                }
                guard let finalEvent = currentEvent else { return nil } // Event swallowed by a utility
                
                // 2. Route to App Switcher
                if type == .keyDown {
                    let keyCode = finalEvent.getIntegerValueField(.keyboardEventKeycode)
                    let flags = finalEvent.flags
                    if keyCode == 48, flags.contains(.maskCommand) {
                        let reverse = flags.contains(.maskShift)
                        if UserDefaults.standard.bool(forKey: "enableAppSwitcher"),
                           controller.onHotkey?(reverse) == true {
                            return nil
                        }
                    }
                }
                return Unmanaged.passUnretained(finalEvent)

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
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: userInfo
        ) else {
            print("🚨 FATAL: Event Tap blocked by macOS.")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func reenableTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }
}
