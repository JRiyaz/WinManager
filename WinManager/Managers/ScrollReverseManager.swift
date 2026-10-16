//
//  ScrollReverseManager.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit

final class ScrollReverseManager {
    func handleEvent(_ event: CGEvent) -> CGEvent? {
        guard UserDefaults.standard.bool(forKey: "enableScrollReverse") else { return event }

        // isContinuous != 0 represents continuous touch gestures (Trackpad / Magic Mouse).
        // isContinuous == 0 represents discrete wheel clicks (standard external USB/Bluetooth mouse).
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        if isContinuous != 0 {
            // Do not alter trackpad scrolling so trackpads continue to work naturally
            return event
        }

        // Invert discrete mouse wheel scrolling (Vertical axis)
        let fields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1,
            .scrollWheelEventPointDeltaAxis1,
            .scrollWheelEventFixedPtDeltaAxis1
        ]

        for field in fields {
            let value = event.getIntegerValueField(field)
            if value != 0 {
                event.setIntegerValueField(field, value: -value)
            }
        }

        return event
    }
}

