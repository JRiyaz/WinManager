//
//  ScrollReverseManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import CoreGraphics

final class ScrollReverseManager {
    func handleEvent(_ event: CGEvent) -> CGEvent? {
        guard UserDefaults.standard.bool(forKey: "enableScrollReverse") else { return event }
        
        // Standard click-wheel mice normally emit discrete scroll events. Touch
        // surfaces (trackpads and many Magic Mouse gestures) are continuous and
        // intentionally left unchanged.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else {
            return event
        }
        
        for field in [
            CGEventField.scrollWheelEventDeltaAxis1,
            .scrollWheelEventPointDeltaAxis1,
            .scrollWheelEventFixedPtDeltaAxis1
        ] {
            let value = event.getIntegerValueField(field)
            if value != 0 {
                event.setIntegerValueField(field, value: -value)
            }
        }
        
        return event
    }
}
