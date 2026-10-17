import AppKit
import ApplicationServices

/// Single session event tap. No polling or repeating timers are used here.
final class EventTapController {
    static let syntheticEventTag: Int64 = 0x57494E4D // "WINM"
    
    var onScroll: ((CGEvent) -> CGEvent?)?
    var onKeyEvent: ((CGEvent, CGEventType) -> CGEvent?)?
    var onHotkey: ((Bool) -> Bool)?
    var onModifierReleased: (() -> Void)?
    var onMouseDown: ((CGEvent) -> Bool)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cleaningModeEnabled = false
    private var forwardedKeyDowns = Set<Int64>()
    private var keysHeldBeforeCleaning = Set<Int64>()
    private var suppressedKeyUps = Set<Int64>()
    private var consumeNextLeftMouseUp = false
    private var commandWasDown = false
    
    var isActive: Bool { eventTap != nil }
    
    func start() {
        guard eventTap == nil, PermissionsManager.hasInputMonitoring else { return }
        
        let mask =
        (CGEventMask(1) << CGEventType.scrollWheel.rawValue) |
        (CGEventMask(1) << CGEventType.keyDown.rawValue) |
        (CGEventMask(1) << CGEventType.keyUp.rawValue) |
        (CGEventMask(1) << CGEventType.flagsChanged.rawValue) |
        (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) |
        (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: winManagerEventTapCallback,
            userInfo: userInfo
        ) else {
            return
        }
        
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    func setCleaningMode(_ enabled: Bool) {
        guard cleaningModeEnabled != enabled else { return }
        
        if enabled {
            keysHeldBeforeCleaning = forwardedKeyDowns
        } else {
            keysHeldBeforeCleaning.removeAll()
            suppressedKeyUps.removeAll()
        }
        cleaningModeEnabled = enabled
    }
    
    func stop() {
        setCleaningMode(false)
        
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        
        runLoopSource = nil
        eventTap = nil
        forwardedKeyDowns.removeAll()
        keysHeldBeforeCleaning.removeAll()
        suppressedKeyUps.removeAll()
        consumeNextLeftMouseUp = false
        commandWasDown = false
    }
    
    fileprivate func reenableTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }
    
    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableTap()
            return Unmanaged.passUnretained(event)
        }
        
        switch type {
        case .scrollWheel:
            // ScrollReverseManager handles per-device reversal (mouse reversed, trackpad natural by default).
            let changed = UserDefaults.standard.bool(forKey: "enableScrollReverse")
            ? (onScroll?(event) ?? event)
            : event
            return Unmanaged.passUnretained(changed)
            
        case .leftMouseDown:
            if UserDefaults.standard.bool(forKey: "enableDockClick"),
               onMouseDown?(event) == true {
                consumeNextLeftMouseUp = true
                return nil
            }
            return Unmanaged.passUnretained(event)
            
        case .leftMouseUp:
            if consumeNextLeftMouseUp {
                consumeNextLeftMouseUp = false
                return nil
            }
            return Unmanaged.passUnretained(event)
            
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let synthetic = event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag
            
            if cleaningModeEnabled {
                if !keysHeldBeforeCleaning.contains(keyCode) {
                    suppressedKeyUps.insert(keyCode)
                }
                return nil
            }
            
            var currentEvent = event
            if !synthetic, let handler = onKeyEvent {
                guard let handledEvent = handler(event, .keyDown) else {
                    suppressedKeyUps.insert(keyCode)
                    return nil
                }
                currentEvent = handledEvent
            }
            
            // Use the custom list so hidden/minimized regular apps remain selectable.
            if !synthetic,
               keyCode == 48,
               currentEvent.flags.contains(.maskCommand),
               UserDefaults.standard.bool(forKey: "enableAltTab") {
                let reverse = currentEvent.flags.contains(.maskShift)
                if onHotkey?(reverse) == true {
                    suppressedKeyUps.insert(keyCode)
                    commandWasDown = true
                    return nil
                }
            }
            
            forwardedKeyDowns.insert(keyCode)
            if currentEvent.flags.contains(.maskCommand) {
                commandWasDown = true
            }
            return Unmanaged.passUnretained(currentEvent)
            
        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            if suppressedKeyUps.remove(keyCode) != nil {
                keysHeldBeforeCleaning.remove(keyCode)
                forwardedKeyDowns.remove(keyCode)
                return nil
            }
            
            if cleaningModeEnabled {
                if keysHeldBeforeCleaning.remove(keyCode) != nil {
                    forwardedKeyDowns.remove(keyCode)
                    return Unmanaged.passUnretained(event)
                }
                return nil
            }
            
            let synthetic = event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag
            let changed = synthetic ? event : (onKeyEvent?(event, .keyUp) ?? event)
            forwardedKeyDowns.remove(keyCode)
            return Unmanaged.passUnretained(changed)
            
        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let commandIsDown = event.flags.contains(.maskCommand)
            
            if cleaningModeEnabled {
                if keysHeldBeforeCleaning.contains(keyCode),
                   !Self.modifierIsDown(keyCode: keyCode, flags: event.flags) {
                    keysHeldBeforeCleaning.remove(keyCode)
                    forwardedKeyDowns.remove(keyCode)
                    return Unmanaged.passUnretained(event)
                }
                return nil
            }
            
            if Self.modifierIsDown(keyCode: keyCode, flags: event.flags) {
                forwardedKeyDowns.insert(keyCode)
            } else {
                forwardedKeyDowns.remove(keyCode)
            }
            
            if commandWasDown && !commandIsDown {
                onModifierReleased?()
            }
            commandWasDown = commandIsDown
            return Unmanaged.passUnretained(event)
            
        default:
            return Unmanaged.passUnretained(event)
        }
    }
    
    private static func modifierIsDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 54, 55: return flags.contains(.maskCommand)
        case 56, 60: return flags.contains(.maskShift)
        case 58, 61: return flags.contains(.maskAlternate)
        case 59, 62: return flags.contains(.maskControl)
        case 63: return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }
}

private func winManagerEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let controller = Unmanaged<EventTapController>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return controller.handleEvent(type: type, event: event)
}
