//
//  MyApp.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import SwiftUI
import os

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    @AppStorage("enableAppSwitcher") private var enableAppSwitcher = false
    @AppStorage("enableDockClicks") private var enableDockClicks = true
    @AppStorage("enableAutoQuit") private var enableAutoQuit = false
    @AppStorage("enableQuitProtection") private var enableQuitProtection = true
    @AppStorage("enableCommandX") private var enableCommandX = true
    @AppStorage("enableScrollReverse") private var enableScrollReverse = true
    @AppStorage("enableCleaningMode") private var enableCleaningMode = false
    
    @State private var accessibilityGranted = PermissionsManager.hasAccessibility
    @State private var inputMonitoringGranted = PermissionsManager.hasInputMonitoring
    @State private var inputTapActive = false
    
    private var menuBarImage: NSImage {
        if let image = NSImage(named: "MenuBarIcon"), let copy = image.copy() as? NSImage {
            copy.size = NSSize(width: 14, height: 14)
            copy.isTemplate = true
            return copy
        }
        
        let fallback = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "WinManager"
        ) ?? NSImage(size: NSSize(width: 14, height: 14))
        fallback.size = NSSize(width: 14, height: 14)
        fallback.isTemplate = true
        return fallback
    }
    
    var body: some Scene {
        MenuBarExtra {
            Group {
                if !accessibilityGranted || !inputMonitoringGranted {
                    Text("WinManager needs permissions")
                        .font(.caption)
                    
                    if !accessibilityGranted {
                        Button("Request Accessibility Permission…") {
                            _ = PermissionsManager.requestAccessibilityPrompt()
                        }
                        Button("Open Accessibility Settings…") {
                            PermissionsManager.openAccessibilitySettings()
                        }
                    }
                    
                    if !inputMonitoringGranted {
                        Button("Request Input Monitoring…") {
                            _ = PermissionsManager.requestInputMonitoringPrompt()
                        }
                        Button("Open Input Monitoring Settings…") {
                            PermissionsManager.openInputMonitoringSettings()
                        }
                    }
                    
                    Button("Refresh Permission Status") {
                        refreshPermissionState()
                    }
                    Divider()
                }
                
                if inputMonitoringGranted && !inputTapActive {
                    Text("Global input features are inactive. Refresh permissions to retry.")
                        .font(.caption)
                    Button("Retry Input Tap") {
                        refreshPermissionState()
                    }
                    Divider()
                }
                
                Toggle("App Switcher (⌘Tab)", isOn: $enableAppSwitcher)
                    .onChange(of: enableAppSwitcher) { _, _ in
                        appDelegate.featureController.refreshFeatureState()
                    }
                
                Divider()
                
                Toggle("Dock Click to Minimize", isOn: $enableDockClicks)
                    .onChange(of: enableDockClicks) { _, _ in
                        appDelegate.featureController.refreshFeatureState()
                    }
                
                Toggle("Quit on Last Window Close (Best Effort)", isOn: $enableAutoQuit)
                    .onChange(of: enableAutoQuit) { _, _ in
                        appDelegate.featureController.refreshFeatureState()
                    }
                
                Toggle("Quit Protection (Hold ⌘Q)", isOn: $enableQuitProtection)
                    .onChange(of: enableQuitProtection) { _, _ in
                        appDelegate.featureController.refreshFeatureState()
                    }
                
                Divider()
                
                Toggle("Reverse Conventional Mouse Wheel", isOn: $enableScrollReverse)
                    .onChange(of: enableScrollReverse) { _, _ in
                        appDelegate.featureController.refreshFeatureState()
                    }
                
                Toggle("Finder Cut & Paste (⌘X to Move)", isOn: $enableCommandX)
                    .onChange(of: enableCommandX) { _, _ in
                        appDelegate.featureController.refreshFeatureState()
                    }
                
                Divider()
                
                if enableCleaningMode {
                    Button("Disable Cleaning Mode") {
                        appDelegate.featureController.disableCleaningMode()
                    }
                } else {
                    Button("Cleaning Mode…") {
                        guard confirmCleaningMode() else { return }
                        appDelegate.featureController.enableCleaningMode()
                    }
                }
                
                Divider()
                
                Button("Open Privacy Settings…") {
                    PermissionsManager.openGeneralPrivacySettings()
                }
                
                Button("Quit WinManager") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .onAppear { refreshPermissionState() }
        } label: {
            Image(nsImage: menuBarImage)
        }
        .menuBarExtraStyle(.menu)
    }
    
    private func confirmCleaningMode() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Enable Cleaning Mode?"
        alert.informativeText = "Keyboard input will be blocked for up to 60 seconds. Mouse input remains available. You can disable this mode from the WinManager menu at any time."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enable for 60 Seconds")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    
    private func refreshPermissionState() {
        accessibilityGranted = PermissionsManager.hasAccessibility
        inputMonitoringGranted = PermissionsManager.hasInputMonitoring
        appDelegate.featureController.refreshPermissions()
        inputTapActive = appDelegate.featureController.isInputTapActive
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "AppDelegate")
    let featureController = FeatureController()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        logger.info("WinManager starting")
        featureController.start()
        
        // Request the required privacy permissions on first launch. macOS may
        // suppress repeat prompts; the menu always provides manual recovery paths.
        PermissionsManager.requestMissingPermissionsOnLaunch()
        featureController.refreshPermissions()
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // This only runs when WinManager becomes active; it is not a polling task.
        featureController.refreshPermissions()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        featureController.stop()
    }
}
