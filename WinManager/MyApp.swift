//
//  MyApp.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import AppKit
import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage("enableAltTab") private var enableAltTab = true
    @AppStorage("enableScrollReverse") private var enableScrollReverse = true
    @AppStorage("enableDockClick") private var enableDockClick = true
    @AppStorage("enableAutoQuit") private var enableAutoQuit = false

    var body: some Scene {
        MenuBarExtra("WinManager", systemImage: "command.square") {
            Toggle("Windows-style Cmd + Tab", isOn: $enableAltTab)
                .onChange(of: enableAltTab) { _, value in
                    appDelegate.featureController.setEnabled(value, for: .switcher)
                }

            Toggle("Reverse external mouse scrolling", isOn: $enableScrollReverse)
                .onChange(of: enableScrollReverse) { _, value in
                    appDelegate.featureController.setEnabled(value, for: .scrollReverse)
                }

            Toggle("Dock click to minimize", isOn: $enableDockClick)
                .onChange(of: enableDockClick) { _, value in
                    appDelegate.featureController.setEnabled(value, for: .dockMinimize)
                }

            Toggle("Quit app when last window closes", isOn: $enableAutoQuit)
                .onChange(of: enableAutoQuit) { _, value in
                    appDelegate.featureController.setEnabled(value, for: .autoQuit)
                }

            Divider()

            Button("Open Privacy Settings…") {
                PermissionsManager.openPrivacySettings()
            }

            Button("Quit WinManager") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let featureController = FeatureController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // FIX: Register the default values so the background managers can read them
        UserDefaults.standard.register(defaults: [
            "enableAltTab": true,
            "enableScrollReverse": true,
            "enableDockClick": true,
            "enableAutoQuit": false
        ])
        
        let axTrusted = PermissionsManager.hasAccessibility
        let imTrusted = PermissionsManager.hasInputMonitoring
        print("🚨 DIAGNOSTIC -> Accessibility: \(axTrusted) | Input: \(imTrusted)")
        
        if !axTrusted { PermissionsManager.requestAccessibilityPrompt() }
        
        featureController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        featureController.stop()
    }
}
