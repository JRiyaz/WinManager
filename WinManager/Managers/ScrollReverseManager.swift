import AppKit
import CoreGraphics
import IOKit
import IOKit.hid

/// Distinguishes between mouse and trackpad scroll events, matching the behavior
/// of Pilotmoon Scroll-Reverser so that external mouse wheels scroll in reverse
/// (classic Windows style) while trackpad scrolling remains natural and smooth.
final class ScrollReverseManager {
    enum DeviceCategory {
        case mouse
        case trackpad
    }
    
    // Low-level IOHIDEvent SPI declarations.
    // Core Graphics event deltas and IOHIDEvent scroll fields must stay synchronized
    // so continuous gestures, rubber-banding, and momentum remain fluid without jitter.
    private typealias IOHIDEventRef = OpaquePointer
    private typealias IOHIDEventSenderID = UInt64
    private typealias IOHIDEventField = UInt32
    
    private static let kIOHIDEventTypeScroll: UInt32 = 6
    private static let kIOHIDEventFieldScrollX: IOHIDEventField = (kIOHIDEventTypeScroll << 16) | 0
    private static let kIOHIDEventFieldScrollY: IOHIDEventField = (kIOHIDEventTypeScroll << 16) | 1
    
    private static let copyIOHIDEvent: (@convention(c) (CGEvent) -> IOHIDEventRef?)? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CGEventCopyIOHIDEvent") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CGEvent) -> IOHIDEventRef?).self)
    }()
    
    private static let getSenderID: (@convention(c) (IOHIDEventRef) -> IOHIDEventSenderID)? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "IOHIDEventGetSenderID") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (IOHIDEventRef) -> IOHIDEventSenderID).self)
    }()
    
    private static let getFloatValue: (@convention(c) (IOHIDEventRef, IOHIDEventField) -> Double)? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "IOHIDEventGetFloatValue") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (IOHIDEventRef, IOHIDEventField) -> Double).self)
    }()
    
    private static let setFloatValue: (@convention(c) (IOHIDEventRef, IOHIDEventField, Double) -> Void)? = {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "IOHIDEventSetFloatValue") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (IOHIDEventRef, IOHIDEventField, Double) -> Void).self)
    }()
    
    /// Cached device classifications keyed by IOHID sender ID to minimize IOKit registry lookups.
    private var senderCache = [IOHIDEventSenderID: DeviceCategory]()
    
    func handleEvent(_ event: CGEvent) -> CGEvent? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "enableScrollReverse") else {
            return event
        }
        
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let (device, hidEvent) = classifyDevice(event: event)
        defer {
            if let hidEvent {
                Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(hidEvent)).release()
            }
        }
        
        // Per-device configuration: mice reverse by default, trackpads remain natural by default.
        let reverseMouse = defaults.object(forKey: "scrollReverseMouse") == nil ? true : defaults.bool(forKey: "scrollReverseMouse")
        let reverseTrackpad = defaults.bool(forKey: "scrollReverseTrackpad")
        let reverseHorizontalSetting = defaults.bool(forKey: "scrollReverseHorizontal")
        
        let reverseVertical: Bool
        let reverseHorizontal: Bool
        
        switch device {
        case .mouse:
            reverseVertical = reverseMouse
            // For discrete mice, horizontal scrolling (tilt wheel / Shift+scroll) matches
            // vertical reversal like Scroll-Reverser. For continuous mice, respect explicit horizontal setting.
            reverseHorizontal = (!isContinuous ? reverseMouse : false) || reverseHorizontalSetting
            
        case .trackpad:
            reverseVertical = reverseTrackpad
            // Continuous trackpad gestures keep swipe gestures intact unless horizontal is explicitly requested
            reverseHorizontal = reverseTrackpad && reverseHorizontalSetting
        }
        
        // When neither axis needs reversal (the default for trackpads), pass through untouched.
        guard reverseVertical || reverseHorizontal else {
            return event
        }
        
        // Vertical axis (Axis 1)
        if reverseVertical {
            let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let fixedPtAxis1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let iohidAxis1: Double = {
                guard let hid = hidEvent, let getFloat = Self.getFloatValue else { return 0.0 }
                return getFloat(hid, Self.kIOHIDEventFieldScrollY)
            }()
            
            // Core Graphics internally modifies PointDeltaAxis (8x) and FixedPtDeltaAxis (1x)
            // whenever DeltaAxis is written. Following Scroll-Reverser's design, set DeltaAxis
            // first, then restore the high-resolution fixed-point and point deltas.
            event.setIntegerValueField(
                .scrollWheelEventDeltaAxis1,
                value: Self.negated(axis1)
            )
            event.setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis1,
                value: -fixedPtAxis1
            )
            event.setIntegerValueField(
                .scrollWheelEventPointDeltaAxis1,
                value: Self.negated(pointAxis1)
            )
            if let hid = hidEvent, let setFloat = Self.setFloatValue {
                setFloat(hid, Self.kIOHIDEventFieldScrollY, -iohidAxis1)
            }
        }
        
        // Horizontal axis (Axis 2)
        if reverseHorizontal {
            let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            let fixedPtAxis2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let iohidAxis2: Double = {
                guard let hid = hidEvent, let getFloat = Self.getFloatValue else { return 0.0 }
                return getFloat(hid, Self.kIOHIDEventFieldScrollX)
            }()
            
            event.setIntegerValueField(
                .scrollWheelEventDeltaAxis2,
                value: Self.negated(axis2)
            )
            event.setDoubleValueField(
                .scrollWheelEventFixedPtDeltaAxis2,
                value: -fixedPtAxis2
            )
            event.setIntegerValueField(
                .scrollWheelEventPointDeltaAxis2,
                value: Self.negated(pointAxis2)
            )
            if let hid = hidEvent, let setFloat = Self.setFloatValue {
                setFloat(hid, Self.kIOHIDEventFieldScrollX, -iohidAxis2)
            }
        }
        
        return event
    }
    
    private func classifyDevice(event: CGEvent) -> (category: DeviceCategory, hidEvent: IOHIDEventRef?) {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        
        // Non-continuous scrolling is always a discrete mouse wheel (e.g. traditional USB/Bluetooth mouse).
        guard isContinuous else {
            return (.mouse, nil)
        }
        
        guard let copyFunc = Self.copyIOHIDEvent,
              let hidEvent = copyFunc(event) else {
            // Continuous touch events without HID info default to trackpad so touch gestures remain natural.
            return (.trackpad, nil)
        }
        
        guard let getSender = Self.getSenderID else {
            return (.trackpad, hidEvent)
        }
        
        let senderID = getSender(hidEvent)
        guard senderID != 0 else {
            return (.trackpad, hidEvent)
        }
        
        if let cached = senderCache[senderID] {
            return (cached, hidEvent)
        }
        
        let resolved = resolveDeviceCategory(senderID: senderID)
        senderCache[senderID] = resolved
        return (resolved, hidEvent)
    }
    
    private func resolveDeviceCategory(senderID: IOHIDEventSenderID) -> DeviceCategory {
        let matching = IORegistryEntryIDMatching(senderID)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else {
            // Unidentified continuous devices default to trackpad (natural) so touch surfaces remain untouched.
            return .trackpad
        }
        defer { IOObjectRelease(service) }
        
        // Check driver class conformance
        if conformsToSelfOrParent(service: service, className: "AppleMultitouchTrackpadHIDEventDriver") {
            return .trackpad
        }
        if conformsToSelfOrParent(service: service, className: "AppleMultitouchMouseHIDEventDriver") {
            return .mouse
        }
        
        // Check scroll acceleration type property
        if let accel = IORegistryEntryCreateCFProperty(service, "HIDScrollAccelerationType" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            if accel == "HIDTrackpadScrollAcceleration" {
                return .trackpad
            } else if accel == "HIDMouseScrollAcceleration" {
                return .mouse
            }
        }
        
        // Check product name
        if let product = IORegistryEntryCreateCFProperty(service, kIOHIDProductKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            let lower = product.lowercased()
            if lower.contains("trackpad") {
                return .trackpad
            } else if lower.contains("mouse") {
                return .mouse
            }
        }
        
        return .trackpad
    }
    
    private func conformsToSelfOrParent(service: io_service_t, className: String) -> Bool {
        if IOObjectConformsTo(service, className) != 0 {
            return true
        }
        var parent: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) != KERN_SUCCESS {
            return false
        }
        defer { IOObjectRelease(parent) }
        return IOObjectConformsTo(parent, className) != 0
    }
    
    private static func negated(_ value: Int64) -> Int64 {
        // Negating Int64.min overflows; saturate the single unrepresentable value.
        value == Int64.min ? Int64.max : -value
    }
}

