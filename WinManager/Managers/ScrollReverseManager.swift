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
        
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)

        // Force invert all possible axes, ignoring whether it is a trackpad or mouse
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
