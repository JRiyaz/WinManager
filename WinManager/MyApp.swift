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
    @AppStorage("enableAutoQuit") private var enableAutoQuit = true
    @AppStorage("enableQuitProtection") private var enableQuitProtection = true
    @AppStorage("enableCommandX") private var enableCommandX = true
    @AppStorage("enableScrollReverse") private var enableScrollReverse = true

    private var menuBarImage: NSImage {
        if let image = NSImage(named: "MenuBarIcon") {
            let resized = image.copy() as! NSImage
            resized.size = NSSize(width: 14, height: 14)
            resized.isTemplate = true
            return resized
        }
        let fallback = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "WinManager")!
        fallback.size = NSSize(width: 14, height: 14)
        fallback.isTemplate = true
        return fallback
    }

    var body: some Scene {
        MenuBarExtra {
            // Permission Status & Action Banners
            if !PermissionsManager.hasAccessibility || !PermissionsManager.hasInputMonitoring {
                Text("⚠️ Permissions Required")
                    .font(.caption)

                if !PermissionsManager.hasAccessibility {
                    Button("Grant Accessibility…") {
                        PermissionsManager.openAccessibilitySettings()
                        PermissionsManager.requestAccessibilityPrompt()
                    }
                }

                if !PermissionsManager.hasInputMonitoring {
                    Button("Grant Input Monitoring…") {
                        PermissionsManager.openInputMonitoringSettings()
                        PermissionsManager.requestInputMonitoringPrompt()
                    }
                }

                Button("Check & Reconnect Tap") {
                    appDelegate.featureController.refreshPermissions()
                }

                Divider()
            }

            // Window Management
            Toggle("App Switcher (⌘Tab)", isOn: $enableAppSwitcher)

            Divider()

            // Dock & Apps
            Toggle("Dock Click to Minimize", isOn: $enableDockClicks)
            Toggle("Quit on Last Window Close", isOn: $enableAutoQuit)
            Toggle("Quit Protection (Hold ⌘Q)", isOn: $enableQuitProtection)

            Divider()

            // System Utilities
            Toggle("Scroll Reverse (External Mouse)", isOn: $enableScrollReverse)
            Toggle("Finder Cut & Paste (⌘X to Move)", isOn: $enableCommandX)

            Divider()

            Button("Open Privacy Settings…") {
                PermissionsManager.openGeneralPrivacySettings()
            }

            Button("Quit WinManager") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(nsImage: menuBarImage)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.riyazjpersonalteam.WinManager", category: "AppDelegate")
    let featureController = FeatureController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let axTrusted = PermissionsManager.hasAccessibility
        let imTrusted = PermissionsManager.hasInputMonitoring
        logger.info("WinManager Launch -> Accessibility: \(axTrusted) | Input Monitoring: \(imTrusted)")

        // Request both necessary permissions at startup
        PermissionsManager.requestAllPermissions()

        featureController.start()

        // Recheck permissions and reconnect tap when user switches back to the app
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.featureController.refreshPermissions()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        featureController.stop()
    }
}

