import AppKit

final class FeatureController {
    private let eventTapController = EventTapController()
    private let scrollManager = ScrollReverseManager()
    private let commandXManager = CommandXManager()
    private let switcherManager = SwitcherManager()
    private let dockManager = DockManager()
    private let windowCloseManager = WindowCloseManager()
    private let displayMoveManager = DisplayMoveManager()
    
    private var cleaningModeTimeout: DispatchWorkItem?
    private var defaultsObserver: NSObjectProtocol?
    private var started = false
    
    var isEventTapActive: Bool { eventTapController.isActive }
    var isCleaningModeEnabled: Bool { UserDefaults.standard.bool(forKey: "enableCleaningMode") }
    
    init() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.synchronizeFeatureState()
        }
    }
    
    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }
    
    func start() {
        guard !started else {
            refreshPermissions()
            return
        }
        started = true
        
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "enableAutoQuit": true,
            "enableScrollReverse": true,
            "scrollReverseMouse": true,
            "scrollReverseTrackpad": false,
            "scrollReverseHorizontal": false,
            "enableCommandX": true,
            "enableDockClick": true,
            "enableAltTab": true,
            "enableCleaningMode": false,
            "enableDisplayMove": true,
            "enableWindowSnap": true
        ])
        
        // Do not leave input locked following an app restart.
        defaults.set(false, forKey: "enableCleaningMode")
        eventTapController.setCleaningMode(false)
        
        eventTapController.onScroll = { [weak self] event in
            self?.scrollManager.handleEvent(event) ?? event
        }
        
        eventTapController.onKeyEvent = { [weak self] event, type in
            guard let self else { return event }
            
            if type == .keyDown {
                if self.displayMoveManager.handleKeyDown(event) {
                    return nil // Suppress original shortcut.
                }
                
                if UserDefaults.standard.bool(forKey: "enableCommandX"),
                   self.commandXManager.handleKeyDown(event) {
                    return nil // Suppress original physical Cmd+X/Cmd+V.
                }
            }
            
            return event
        }
        
        eventTapController.onHotkey = { [weak self] reverse in
            guard let self else { return false }
            return self.switcherManager.handleSwitchHotkey(reverse: reverse)
        }
        
        eventTapController.onModifierReleased = { [weak self] in
            self?.switcherManager.executeSwitch()
        }
        
        eventTapController.onMouseDown = { [weak self] event in
            guard let self,
                  UserDefaults.standard.bool(forKey: "enableDockClick") else {
                return false
            }
            return self.dockManager.handleMouseDown(event)
        }
        
        eventTapController.start()
        synchronizeFeatureState()
    }
    
    func stop() {
        cleaningModeTimeout?.cancel()
        cleaningModeTimeout = nil
        eventTapController.setCleaningMode(false)
        UserDefaults.standard.set(false, forKey: "enableCleaningMode")
        eventTapController.stop()
        windowCloseManager.stop()
        switcherManager.dismiss()
        started = false
    }
    
    func refreshPermissions() {
        if PermissionsManager.hasInputMonitoring && !eventTapController.isActive {
            eventTapController.start()
        }
        synchronizeFeatureState()
    }
    
    func enableCleaningMode(duration: TimeInterval = 60) {
        guard eventTapController.isActive else {
            return
        }
        
        disableCleaningMode()
        eventTapController.setCleaningMode(true)
        UserDefaults.standard.set(true, forKey: "enableCleaningMode")
        
        let timeout = DispatchWorkItem { [weak self] in
            self?.disableCleaningMode()
        }
        cleaningModeTimeout = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(1, duration),
            execute: timeout
        )
    }
    
    func disableCleaningMode() {
        cleaningModeTimeout?.cancel()
        cleaningModeTimeout = nil
        eventTapController.setCleaningMode(false)
        UserDefaults.standard.set(false, forKey: "enableCleaningMode")
    }
    
    private func synchronizeFeatureState() {
        guard started else { return }
        
        if UserDefaults.standard.bool(forKey: "enableAutoQuit"),
           PermissionsManager.hasAccessibility {
            windowCloseManager.start()
        } else {
            windowCloseManager.stop()
        }
        
        if !UserDefaults.standard.bool(forKey: "enableAltTab") {
            switcherManager.dismiss()
        }
    }
}
