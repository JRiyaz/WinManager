import AppKit
import Combine
import ApplicationServices

struct SwitcherItem: Identifiable {
    let id: pid_t
    let app: NSRunningApplication
    var name: String { app.localizedName ?? app.bundleIdentifier ?? "Unknown App" }
    var icon: NSImage { app.icon ?? NSImage(size: NSSize(width: 48, height: 48)) }
}

final class SwitcherViewModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selectedIndex: Int = 0
}

/// App-level switcher. Hidden/minimized regular apps are deliberately not filtered out.
final class SwitcherManager {
    private let model = SwitcherViewModel()
    private var panel: NSPanel?
    private var switcherView: AltTabOverlayView?
    private var isShowing = false
    private var mostRecentPIDs: [pid_t] = []
    private var activationObserver: NSObjectProtocol?
    
    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.recordActivation(app.processIdentifier)
        }
        
        if let active = NSWorkspace.shared.frontmostApplication {
            recordActivation(active.processIdentifier)
        }
    }
    
    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }
    
    /// Returns true only when our app-list switcher opened or advanced.
    @discardableResult
    func handleSwitchHotkey(reverse: Bool) -> Bool {
        refreshItems()
        guard !model.items.isEmpty else { return false }
        
        if !isShowing {
            isShowing = true
            model.selectedIndex = initialIndex(reverse: reverse)
            showPanel()
            return panel != nil
        }
        
        let count = model.items.count
        model.selectedIndex = (model.selectedIndex + (reverse ? count - 1 : 1)) % count
        return true
    }
    
    func executeSwitch() {
        guard isShowing, model.items.indices.contains(model.selectedIndex) else {
            dismiss()
            return
        }
        
        let app = model.items[model.selectedIndex].app
        dismiss()
        
        guard !app.isTerminated else { return }
        if app.isHidden {
            _ = app.unhide()
        }
        
        // Activation is requested first; Accessibility restores a minimized real window after.
        _ = app.activate(options: [])
        recordActivation(app.processIdentifier)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self, weak app] in
            guard let self, let app, !app.isTerminated else { return }
            self.restoreAndRaiseWindow(for: app)
        }
    }
    
    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        switcherView = nil
        isShowing = false
    }
    
    private func refreshItems() {
        let running = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated &&
            $0.activationPolicy == .regular &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        
        // Do not filter isHidden: apps whose windows are minimized or whose app is hidden
        // remain in the switcher as long as macOS reports them as regular running apps.
        model.items = running.sorted { first, second in
            let firstIndex = mostRecentPIDs.firstIndex(of: first.processIdentifier) ?? Int.max
            let secondIndex = mostRecentPIDs.firstIndex(of: second.processIdentifier) ?? Int.max
            if firstIndex != secondIndex { return firstIndex < secondIndex }
            return (first.localizedName ?? "").localizedCaseInsensitiveCompare(second.localizedName ?? "") == .orderedAscending
        }.map { SwitcherItem(id: $0.processIdentifier, app: $0) }
        
        if model.items.isEmpty {
            model.selectedIndex = 0
        } else if model.selectedIndex >= model.items.count {
            model.selectedIndex = 0
        }
    }
    
    private func initialIndex(reverse: Bool) -> Int {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let index = model.items.firstIndex(where: { $0.id == frontmost.processIdentifier }) else {
            return 0
        }
        let count = model.items.count
        return (index + (reverse ? count - 1 : 1)) % count
    }
    
    private func recordActivation(_ pid: pid_t) {
        mostRecentPIDs.removeAll { $0 == pid }
        mostRecentPIDs.insert(pid, at: 0)
    }
    
    private func showPanel() {
        let screen = preferredScreen()
        let visible = (screen ?? NSScreen.main)?.visibleFrame ??
        NSRect(x: 0, y: 0, width: 1024, height: 768)
        
        // Keep the custom HUD compact while allowing the icon strip to scroll for large app lists.
        let itemCount = CGFloat(model.items.count)
        let desiredWidth = itemCount * AltTabOverlayView.cellSize.width
        + CGFloat(max(0, model.items.count - 1)) * AltTabOverlayView.cellSpacing
        + 36 // 18 pt outer inset on each side
        let width = min(max(280, desiredWidth), max(280, visible.width - 32))
        let height: CGFloat = 172
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        
        let switcherView = AltTabOverlayView(
            frame: NSRect(x: 0, y: 0, width: width, height: height),
            model: model
        )
        panel.contentView = switcherView
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2
        ))
        panel.orderFrontRegardless()
        
        self.switcherView = switcherView
        self.panel = panel
    }
    
    private func preferredScreen() -> NSScreen? {
        if let screen = screenContainingFrontmostWindow() {
            return screen
        }
        
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }
    
    private func screenContainingFrontmostWindow() -> NSScreen? {
        guard PermissionsManager.hasAccessibility,
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value) == .success,
                  let value,
                  CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            
            let window = unsafeBitCast(value, to: AXUIElement.self)
            guard let rect = accessibilityRect(of: window) else { continue }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                if CGDisplayBounds(CGDirectDisplayID(number.uint32Value)).contains(center) {
                    return screen
                }
            }
        }
        return nil
    }
    
    private func accessibilityRect(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        
        let positionAXValue = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
    
    private func restoreAndRaiseWindow(for app: NSRunningApplication) {
        guard PermissionsManager.hasAccessibility else { return }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.4)
        
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              !windows.isEmpty else {
            return
        }
        
        var candidates: [AXUIElement] = []
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var windowValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, attribute as CFString, &windowValue) == .success,
               let windowValue,
               CFGetTypeID(windowValue) == AXUIElementGetTypeID() {
                candidates.append(unsafeBitCast(windowValue, to: AXUIElement.self))
            }
        }
        candidates.append(contentsOf: windows)
        
        for window in candidates {
            AXUIElementSetMessagingTimeout(window, 0.4)
            
            var minimizedValue: CFTypeRef?
            let minimizedQueryOK = AXUIElementCopyAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                &minimizedValue
            ) == .success
            let isMinimized = minimizedQueryOK && ((minimizedValue as? Bool) == true)
            
            if isMinimized {
                let restore = AXUIElementSetAttributeValue(
                    window,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanFalse
                )
                guard restore == .success else { continue }
            }
            
            if AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success {
                return
            }
        }
    }
}
