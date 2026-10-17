import AppKit
import ApplicationServices

/// Manages moving the focused window between connected displays and snapping windows
/// to screen regions (Left Half, Right Half, Full Screen, and Default Centered Size).
/// Based on the algorithms from Rectangle (rxhanson/Rectangle).
final class DisplayMoveManager {
    
    enum Direction {
        case next
        case previous
    }
    
    enum SnapAction {
        case leftHalf
        case rightHalf
        case fullScreen
        case defaultSize // Centered with default width and height
    }
    
    /// Handles a key down event from the event tap.
    /// Returns true if the event was handled and should be suppressed from the system.
    func handleKeyDown(_ event: CGEvent) -> Bool {
        guard PermissionsManager.hasAccessibility else {
            return false
        }
        
        let flags = event.flags
        let isControl = flags.contains(.maskControl)
        let isOption = flags.contains(.maskAlternate)
        let isCommand = flags.contains(.maskCommand)
        let isShift = flags.contains(.maskShift)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // MARK: - 1. Window Snapping (Control + Option, without Command or Shift)
        if UserDefaults.standard.bool(forKey: "enableWindowSnap"),
           isControl && isOption && !isCommand && !isShift {
            let snapAction: SnapAction?
            switch keyCode {
            case 123: // Left Arrow -> Left Half
                snapAction = .leftHalf
            case 124: // Right Arrow -> Right Half
                snapAction = .rightHalf
            case 36, 126: // Return or Up Arrow -> Full Screen (Maximize)
                snapAction = .fullScreen
            case 8, 125: // C or Down Arrow -> Default Size (Centered)
                snapAction = .defaultSize
            default:
                snapAction = nil
            }
            
            if let snapAction {
                DispatchQueue.main.async { [weak self] in
                    self?.snapActiveWindow(action: snapAction)
                }
                return true
            }
        }
        
        // MARK: - 2. Display Moving (2-3 keys: ⌃⌘ or ⌥⌘, or legacy 4 keys: ⌃⌥⌘)
        if UserDefaults.standard.bool(forKey: "enableDisplayMove"), !isShift {
            let isDisplayMoveModifiers =
            (isControl && isCommand && !isOption) || // ⌃⌘ (3 keys)
            (isOption && isCommand && !isControl) ||  // ⌥⌘ (3 keys)
            (isControl && isOption && isCommand)      // ⌃⌥⌘ (4 keys)
            
            if isDisplayMoveModifiers {
                let direction: Direction?
                switch keyCode {
                case 124: // Right Arrow -> Next Display
                    direction = .next
                case 123: // Left Arrow -> Previous Display
                    direction = .previous
                default:
                    direction = nil
                }
                
                if let direction {
                    DispatchQueue.main.async { [weak self] in
                        self?.moveActiveWindow(direction: direction)
                    }
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Window Snapping
    
    /// Snaps the focused window to a target layout (Left, Right, Full Screen, or Default Size)
    /// within its current display's visible bounds.
    func snapActiveWindow(action: SnapAction) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              !frontApp.isTerminated else {
            return
        }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        
        guard let windowElement = getFocusedWindow(for: appElement) else {
            return
        }
        
        if isWindowFullScreen(windowElement) {
            return
        }
        
        guard let currentAXFrame = getWindowFrame(windowElement) else {
            return
        }
        
        let primaryHeight = screens[0].frame.height
        let windowCocoaRect = axToCocoa(rect: currentAXFrame, primaryScreenHeight: primaryHeight)
        let screen = findSourceScreen(for: windowCocoaRect, screens: screens)
        let visible = screen.visibleFrame
        
        let targetCocoaRect: CGRect
        switch action {
        case .leftHalf:
            let width = round(visible.width / 2)
            targetCocoaRect = CGRect(
                x: visible.minX,
                y: visible.minY,
                width: width,
                height: visible.height
            )
        case .rightHalf:
            let width = round(visible.width / 2)
            targetCocoaRect = CGRect(
                x: visible.maxX - width,
                y: visible.minY,
                width: width,
                height: visible.height
            )
        case .fullScreen:
            targetCocoaRect = CGRect(
                x: visible.minX,
                y: visible.minY,
                width: visible.width,
                height: visible.height
            )
        case .defaultSize:
            let defaultWidth = min(visible.width, max(round(visible.width * 0.70), 960))
            let defaultHeight = min(visible.height, max(round(visible.height * 0.80), 640))
            targetCocoaRect = CGRect(
                x: round(visible.minX + (visible.width - defaultWidth) / 2),
                y: round(visible.minY + (visible.height - defaultHeight) / 2),
                width: defaultWidth,
                height: defaultHeight
            )
        }
        
        let targetAXRect = cocoaToAX(rect: targetCocoaRect, primaryScreenHeight: primaryHeight)
        setWindowFrame(windowElement, targetRect: targetAXRect)
    }
    
    // MARK: - Display Moving
    
    /// Moves the frontmost application's focused window to the next or previous display.
    func moveActiveWindow(direction: Direction) {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            // Cannot move between displays if only one display is connected.
            return
        }
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              !frontApp.isTerminated else {
            return
        }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        
        // Retrieve the focused window, falling back to the main window.
        guard let windowElement = getFocusedWindow(for: appElement) else {
            return
        }
        
        // Skip native full-screen windows (macOS spaces manage those).
        if isWindowFullScreen(windowElement) {
            return
        }
        
        // Get current window frame in AX coordinates.
        guard let currentAXFrame = getWindowFrame(windowElement) else {
            return
        }
        
        let primaryHeight = screens[0].frame.height
        let windowCocoaRect = axToCocoa(rect: currentAXFrame, primaryScreenHeight: primaryHeight)
        
        // Identify the current screen the window resides on.
        let sourceScreen = findSourceScreen(for: windowCocoaRect, screens: screens)
        
        // Order screens and pick the adjacent destination screen.
        let orderedScreens = orderScreens(screens)
        guard let destinationScreen = getAdjacentScreen(
            from: sourceScreen,
            in: orderedScreens,
            direction: direction
        ) else {
            return
        }
        
        let sourceVisible = sourceScreen.visibleFrame
        let destVisible = destinationScreen.visibleFrame
        
        // Compute the new frame using Rectangle's edge-preserving and proportional transfer logic.
        let newCocoaRect = transferredRect(
            window: windowCocoaRect,
            source: sourceVisible,
            destination: destVisible
        )
        
        let newAXRect = cocoaToAX(rect: newCocoaRect, primaryScreenHeight: primaryHeight)
        setWindowFrame(windowElement, targetRect: newAXRect)
    }
    
    // MARK: - Accessibility Helpers
    
    private func getFocusedWindow(for appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let element = value, CFGetTypeID(element) == AXUIElementGetTypeID() {
            return (element as! AXUIElement)
        }
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &value) == .success,
           let element = value, CFGetTypeID(element) == AXUIElementGetTypeID() {
            return (element as! AXUIElement)
        }
        return nil
    }
    
    private func isWindowFullScreen(_ windowElement: AXUIElement) -> Bool {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, "AXFullScreen" as CFString, &value) == .success,
           let isFS = value as? Bool {
            return isFS
        }
        return false
    }
    
    private func getWindowFrame(_ windowElement: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posVal = posValue, CFGetTypeID(posVal) == AXValueGetTypeID(),
              let sizeVal = sizeValue, CFGetTypeID(sizeVal) == AXValueGetTypeID() else {
            return nil
        }
        
        var point = CGPoint.zero
        var size = CGSize.zero
        
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else {
            return nil
        }
        
        return CGRect(origin: point, size: size)
    }
    
    private func setWindowFrame(_ windowElement: AXUIElement, targetRect: CGRect) {
        var origin = targetRect.origin
        var size = targetRect.size
        
        guard let originValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        
        // Multi-step adjustment (from Rectangle's AccessibilityElement.setFrame):
        // 1. Set size: shrinks the window if necessary before moving across displays or resizing.
        // 2. Set position: moves window to target position.
        // 3. Set size: expands the window if display has more space.
        // 4. Set position: re-anchors the position in case resizing caused an origin shift.
        AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, originValue)
    }
    
    // MARK: - Screen Coordinate Conversions
    
    private func axToCocoa(rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let cocoaY = primaryScreenHeight - (rect.origin.y + rect.size.height)
        return CGRect(x: rect.origin.x, y: cocoaY, width: rect.size.width, height: rect.size.height)
    }
    
    private func cocoaToAX(rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let axY = primaryScreenHeight - (rect.origin.y + rect.size.height)
        return CGRect(x: rect.origin.x, y: axY, width: rect.size.width, height: rect.size.height)
    }
    
    // MARK: - Screen Detection and Ordering
    
    private func findSourceScreen(for cocoaRect: CGRect, screens: [NSScreen]) -> NSScreen {
        var bestScreen = screens[0]
        var maxArea: CGFloat = -1
        
        for screen in screens {
            let frame = screen.frame
            if frame.contains(cocoaRect) {
                return screen
            }
            let intersection = cocoaRect.intersection(frame)
            if !intersection.isNull {
                let area = intersection.width * intersection.height
                if area > maxArea {
                    maxArea = area
                    bestScreen = screen
                }
            }
        }
        return bestScreen
    }
    
    private func orderScreens(_ screens: [NSScreen]) -> [NSScreen] {
        screens.sorted { s1, s2 in
            if abs(s1.frame.minX - s2.frame.minX) > 10 {
                return s1.frame.minX < s2.frame.minX
            }
            return s1.frame.minY < s2.frame.minY
        }
    }
    
    private func getAdjacentScreen(
        from source: NSScreen,
        in screens: [NSScreen],
        direction: Direction
    ) -> NSScreen? {
        guard screens.count > 1 else { return nil }
        
        if screens.count == 2 {
            return screens.first { $0 != source } ?? screens.first
        }
        
        guard let currentIndex = screens.firstIndex(where: { $0 == source }) else {
            return screens.first
        }
        
        let count = screens.count
        switch direction {
        case .next:
            let nextIndex = (currentIndex + 1) % count
            return screens[nextIndex]
        case .previous:
            let prevIndex = (currentIndex - 1 + count) % count
            return screens[prevIndex]
        }
    }
    
    // MARK: - Display Transfer Algorithm (Rectangle DisplayTransfer.swift)
    
    private typealias Span = (origin: CGFloat, length: CGFloat)
    
    private enum Contact {
        case neither, start, end, both
        var isOneEdge: Bool { self == .start || self == .end }
    }
    
    /// Calculates the target window rect when moving from `source` to `destination` display frame.
    /// Preserves edge snapping (e.g. half-screen or maximized), proportional centering,
    /// and adapts intelligently across landscape/portrait transitions.
    private func transferredRect(
        window: CGRect,
        source: CGRect,
        destination: CGRect,
        edgeTolerance: CGFloat = 4
    ) -> CGRect {
        guard source.width > 0, source.height > 0,
              destination.width > 0, destination.height > 0 else {
            return window
        }
        
        var horizontal = transferSpan(
            window: (window.minX, window.width),
            source: (source.minX, source.width),
            destination: (destination.minX, destination.width),
            edgeTolerance: edgeTolerance
        )
        
        var vertical = transferSpan(
            window: (window.minY, window.height),
            source: (source.minY, source.height),
            destination: (destination.minY, destination.height),
            edgeTolerance: edgeTolerance
        )
        
        // Handle landscape <-> portrait orientation change:
        // If window touches 3 edges (e.g. left-half: spanning vertically and touching left edge),
        // keep its size and center it along the edge instead of stretching it awkwardly.
        if changesOrientation(from: source, to: destination) {
            if horizontal.contact == .both && vertical.contact.isOneEdge {
                horizontal.span = centered(
                    length: window.width,
                    on: horizontal.span,
                    destination: (destination.minX, destination.width)
                )
            } else if vertical.contact == .both && horizontal.contact.isOneEdge {
                vertical.span = centered(
                    length: window.height,
                    on: vertical.span,
                    destination: (destination.minY, destination.height)
                )
            }
        }
        
        return CGRect(
            x: horizontal.span.origin,
            y: vertical.span.origin,
            width: horizontal.span.length,
            height: vertical.span.length
        )
    }
    
    private func changesOrientation(from source: CGRect, to destination: CGRect) -> Bool {
        (source.width > source.height && destination.height > destination.width)
        || (source.height > source.width && destination.width > destination.height)
    }
    
    private func centered(length: CGFloat, on spanned: Span, destination: Span) -> Span {
        guard length < spanned.length else { return spanned }
        return (destination.origin + (destination.length - length) / 2, length)
    }
    
    private func transferSpan(
        window: Span,
        source: Span,
        destination: Span,
        edgeTolerance: CGFloat
    ) -> (span: Span, contact: Contact) {
        let startInset = window.origin - source.origin
        let endInset = (source.origin + source.length) - (window.origin + window.length)
        let againstStart = startInset <= edgeTolerance
        let againstEnd = endInset <= edgeTolerance
        
        // Spanning both edges (e.g. full width / full height / maximized)
        if againstStart && againstEnd {
            let start = clamp(startInset, min: 0, max: destination.length / 2)
            let end = clamp(endInset, min: 0, max: destination.length / 2)
            return ((destination.origin + start, max(1, destination.length - start - end)), .both)
        }
        
        let length = min(window.length, destination.length)
        let slack = destination.length - length
        
        // Against leading edge (left or bottom)
        if againstStart {
            return ((destination.origin + clamp(startInset, min: 0, max: slack), length), .start)
        }
        
        // Against trailing edge (right or top)
        if againstEnd {
            return ((destination.origin + destination.length - length - clamp(endInset, min: 0, max: slack), length), .end)
        }
        
        // Floating window: preserve relative center fraction
        let centerFraction = (window.origin + window.length / 2 - source.origin) / source.length
        let origin = destination.origin + centerFraction * destination.length - length / 2
        return ((clamp(origin, min: destination.origin, max: destination.origin + slack), length), .neither)
    }
    
    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }
}
