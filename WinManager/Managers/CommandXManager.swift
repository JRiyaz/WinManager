import AppKit
import ApplicationServices

/// Emulates Finder's cut/move workflow using public keyboard and pasteboard APIs.
/// Finder receives Cmd+C, then Cmd+Option+V when the user pastes the unchanged file clipboard.
final class CommandXManager {
    private var fileIsCut = false
    private var cutPasteboardChangeCount: Int?
    private var pendingCopyGeneration: UInt64 = 0
    private var workspaceObserver: NSObjectProtocol?
    
    init() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            if app.bundleIdentifier != "com.apple.finder" {
                self.resetCutState()
            }
        }
    }
    
    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }
    
    /// Returns true only when the original physical key-down must be suppressed.
    func handleKeyDown(_ event: CGEvent) -> Bool {
        guard UserDefaults.standard.bool(forKey: "enableCommandX") else { return false }
        guard event.getIntegerValueField(.eventSourceUserData) != EventTapController.syntheticEventTag else {
            return false
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let commandDown = flags.contains(.maskCommand)
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == "com.apple.finder" else {
            if fileIsCut { resetCutState() }
            return false
        }
        
        if keyCode == 53 { // Escape cancels the pending cut state.
            resetCutState()
            return false
        }
        
        if keyCode == 8, commandDown { // A normal Cmd+C replaces the cut operation.
            resetCutState()
            return false
        }
        
        if keyCode == 7, commandDown { // Cmd+X -> Finder Cmd+C.
            let pasteboard = NSPasteboard.general
            let oldChangeCount = pasteboard.changeCount
            resetCutState()
            pendingCopyGeneration &+= 1
            let generation = pendingCopyGeneration
            
            postSyntheticKey(keyCode: 8, flags: [.maskCommand])
            
            // One short, one-shot delay gives Finder time to update the pasteboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self,
                      self.pendingCopyGeneration == generation else { return }
                
                let updatedPasteboard = NSPasteboard.general
                let hasFiles = updatedPasteboard.canReadItem(
                    withDataConformingToTypes: [NSPasteboard.PasteboardType.fileURL.rawValue]
                )
                guard updatedPasteboard.changeCount != oldChangeCount, hasFiles else {
                    self.resetCutState()
                    return
                }
                
                self.cutPasteboardChangeCount = updatedPasteboard.changeCount
                self.fileIsCut = true
            }
            return true
        }
        
        if keyCode == 9, commandDown, fileIsCut { // Cmd+V -> Cmd+Option+V.
            let pasteboard = NSPasteboard.general
            let hasFiles = pasteboard.canReadItem(
                withDataConformingToTypes: [NSPasteboard.PasteboardType.fileURL.rawValue]
            )
            
            guard hasFiles,
                  let expectedChangeCount = cutPasteboardChangeCount,
                  pasteboard.changeCount == expectedChangeCount else {
                resetCutState()
                return false
            }
            
            resetCutState()
            postSyntheticKey(keyCode: 9, flags: [.maskCommand, .maskAlternate])
            return true
        }
        
        return false
    }
    
    func resetCutState() {
        pendingCopyGeneration &+= 1
        fileIsCut = false
        cutPasteboardChangeCount = nil
    }
    
    private func postSyntheticKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        
        for event in [keyDown, keyUp] {
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: EventTapController.syntheticEventTag)
        }
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
