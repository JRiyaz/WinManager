//
//  ScrollManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import CoreGraphics

struct ScrollManager {
    /// Reverses only discrete (typically wheel-mouse) vertical scrolling.
    /// Continuous trackpad events are passed through unchanged.
    func transform(_ event: CGEvent) -> CGEvent? {
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !isContinuous else { return event }

        for field in [
            CGEventField.scrollWheelEventDeltaAxis1,
            CGEventField.scrollWheelEventFixedPtDeltaAxis1,
            CGEventField.scrollWheelEventPointDeltaAxis1
        ] {
            let value = event.getIntegerValueField(field)
            event.setIntegerValueField(field, value: -value)
        }
        return event
    }
}
