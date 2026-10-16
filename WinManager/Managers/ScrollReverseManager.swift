import AppKit
import CoreGraphics

/// Reverses vertical scrolling for discrete wheel and continuous/high-resolution events.
final class ScrollReverseManager {
    func handleEvent(_ event: CGEvent) -> CGEvent? {
        guard UserDefaults.standard.bool(forKey: "enableScrollReverse") else {
            return event
        }
        
        // Read every original value before mutating anything. Core Graphics may update
        // PointDelta and FixedPtDelta automatically when DeltaAxis is changed, so reading
        // these fields in a mutation loop can negate an already-modified value and undo
        // the reversal on high-resolution scroll devices.
        let verticalDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let verticalPointDelta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let verticalFixedPointDelta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        
        // DeltaAxis is line-based; FixedPtDelta preserves the 16.16 high-resolution value;
        // PointDelta carries pixel-based scrolling. Keep horizontal fields untouched.
        event.setIntegerValueField(
            .scrollWheelEventDeltaAxis1,
            value: Self.negated(verticalDelta)
        )
        event.setDoubleValueField(
            .scrollWheelEventFixedPtDeltaAxis1,
            value: -verticalFixedPointDelta
        )
        event.setIntegerValueField(
            .scrollWheelEventPointDeltaAxis1,
            value: Self.negated(verticalPointDelta)
        )
        
        return event
    }
    
    private static func negated(_ value: Int64) -> Int64 {
        // Negating Int64.min overflows; saturate the single unrepresentable value.
        value == Int64.min ? Int64.max : -value
    }
}
