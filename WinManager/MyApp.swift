import AppKit
import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate: AppDelegate
    
    @AppStorage("enableAutoQuit") private var enableAutoQuit = true
    @AppStorage("enableScrollReverse") private var enableScrollReverse = true
    @AppStorage("scrollReverseMouse") private var scrollReverseMouse = true
    @AppStorage("scrollReverseTrackpad") private var scrollReverseTrackpad = false
    @AppStorage("scrollReverseHorizontal") private var scrollReverseHorizontal = false
    @AppStorage("enableCommandX") private var enableCommandX = true
    @AppStorage("enableDockClick") private var enableDockClick = true
    @AppStorage("enableAltTab") private var enableAltTab = true
    @AppStorage("enableCleaningMode") private var enableCleaningMode = false
    
    /// A monochrome template version of the Win Manager mark for the menu bar.
    /// MenuBarIcon is kept separate from the full-color square application icon so it
    /// remains legible in both light and dark menu-bar appearances.
    private var statusIcon: NSImage {
        let image = NSImage(named: NSImage.Name("MenuBarIcon"))
        ?? NSImage(systemSymbolName: "command.square", accessibilityDescription: "Win Manager")
        ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 12)
        return image
    }
    
    var body: some Scene {
        MenuBarExtra {
            Label {
                Text("Win Manager")
            } icon: {
                Image(nsImage: statusIcon)
                    .renderingMode(.template)
            }
            .font(.headline)
            .disabled(true)
            
            // Divider 1: app name and features.
            Divider()
            
            Toggle("Quit on Close", isOn: $enableAutoQuit)
            Toggle("Scroll Reverse", isOn: $enableScrollReverse)
            Menu("    Scroll Options") {
                Toggle("Reverse Mouse", isOn: $scrollReverseMouse)
                Toggle("Reverse Trackpad", isOn: $scrollReverseTrackpad)
                Divider()
                Toggle("Reverse Horizontal", isOn: $scrollReverseHorizontal)
            }
            .disabled(!enableScrollReverse)
            Toggle("Cut & Paste", isOn: $enableCommandX)
            Toggle("Dock Clicks", isOn: $enableDockClick)
            Toggle("App Switcher", isOn: $enableAltTab)
            
            Button(enableCleaningMode ? "Stop Clean Mode" : "Clean Mode…") {
                if enableCleaningMode {
                    appDelegate.featureController.disableCleaningMode()
                    return
                }
                
                let alert = NSAlert()
                alert.messageText = "Enable Clean Mode?"
                alert.informativeText = """
                Keyboard input will be blocked for 60 seconds. Mouse input stays available.
                You can turn Clean Mode off from the Win Manager menu.
                """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Enable for 60 Seconds")
                alert.addButton(withTitle: "Cancel")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    appDelegate.featureController.enableCleaningMode(duration: 60)
                }
            }
            .disabled(!PermissionsManager.hasInputMonitoring)
            
            // Divider 2: features and privacy/quit actions.
            Divider()
            
            Button("Privacy & Security…") {
                PermissionsManager.openPrivacySettings()
            }
            
            Button("Quit Win Manager") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(nsImage: statusIcon)
                .renderingMode(.template)
                .accessibilityLabel("Win Manager")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let featureController = FeatureController()
    private var workspaceObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let defaults = UserDefaults.standard
        
        // One-time migration: the requested product defaults are to enable every feature
        // except Clean Mode. Existing installs receive those defaults once on this revision;
        // after this migration, the user's menu toggles are respected across launches.
        let defaultsMigrationKey = "winManagerFeatureDefaultsMigrationVersion"
        if defaults.integer(forKey: defaultsMigrationKey) < 1 {
            defaults.set(true, forKey: "enableAutoQuit")
            defaults.set(true, forKey: "enableScrollReverse")
            defaults.set(true, forKey: "scrollReverseMouse")
            defaults.set(false, forKey: "scrollReverseTrackpad")
            defaults.set(false, forKey: "scrollReverseHorizontal")
            defaults.set(true, forKey: "enableCommandX")
            defaults.set(true, forKey: "enableDockClick")
            defaults.set(true, forKey: "enableAltTab")
            defaults.set(false, forKey: "enableCleaningMode")
            defaults.set(1, forKey: defaultsMigrationKey)
        }
        
        // Migrate old Dock setting name to the single key used by this source set.
        if defaults.object(forKey: "enableDockClick") == nil,
           let oldValue = defaults.object(forKey: "enableDockClicks") as? Bool {
            defaults.set(oldValue, forKey: "enableDockClick")
        }
        
        if defaults.object(forKey: "scrollReverseMouse") == nil {
            defaults.set(true, forKey: "scrollReverseMouse")
        }
        if defaults.object(forKey: "scrollReverseTrackpad") == nil {
            defaults.set(false, forKey: "scrollReverseTrackpad")
        }
        if defaults.object(forKey: "scrollReverseHorizontal") == nil {
            defaults.set(false, forKey: "scrollReverseHorizontal")
        }
        
        defaults.register(defaults: [
            "enableAutoQuit": true,
            "enableScrollReverse": true,
            "scrollReverseMouse": true,
            "scrollReverseTrackpad": false,
            "scrollReverseHorizontal": false,
            "enableCommandX": true,
            "enableDockClick": true,
            "enableAltTab": true,
            "enableCleaningMode": false
        ])
        
        // Ask once at launch if either permission is missing. The menu's privacy
        // action remains available if the user dismisses or later revokes access.
        if !PermissionsManager.hasAccessibility {
            _ = PermissionsManager.requestAccessibilityPrompt()
        }
        if !PermissionsManager.hasInputMonitoring {
            _ = PermissionsManager.requestInputMonitoringPrompt()
        }
        
        featureController.start()
        
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.featureController.refreshPermissions()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        featureController.stop()
    }
}
