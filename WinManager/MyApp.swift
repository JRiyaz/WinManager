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
    
    @AppStorage("enableAppSwitcher") private var enableAppSwitcher = false
    @AppStorage("enableWindowLayout") private var enableWindowLayout = false
    @AppStorage("enableDockPreview") private var enableDockPreview = false
    @AppStorage("enableDockClicks") private var enableDockClicks = true
    @AppStorage("enableAutoQuit") private var enableAutoQuit = true
    @AppStorage("enableQuitProtection") private var enableQuitProtection = true
    @AppStorage("enableSideButtons") private var enableSideButtons = false
    @AppStorage("enableCommandX") private var enableCommandX = true
    @AppStorage("enableScrollReverse") private var enableScrollReverse = true
    
    private var menuBarImage: NSImage {
        if let image = NSImage(named: "MenuBarIcon") {
            let resized = image.copy() as! NSImage
            // Reduced to 14x14 to prevent stretching and match smaller system icons
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
            // Window Management
            Toggle("App Switcher (Live Previews)", isOn: $enableAppSwitcher)
            Toggle("Window Layouts (Snapping)", isOn: $enableWindowLayout)
            
            Divider()
            
            // Dock & Apps
            Toggle("Dock Previews", isOn: $enableDockPreview)
            Toggle("Dock Clicks (Minimize/Hide)", isOn: $enableDockClicks)
            Toggle("Quit on Close", isOn: $enableAutoQuit)
            Toggle("Quit Protection (Hold ⌘Q)", isOn: $enableQuitProtection)
            
            Divider()
            
            // System Utilities
            Toggle("Scroll Reverse", isOn: $enableScrollReverse)
            Toggle("Mouse Side Buttons (Back / Forward)", isOn: $enableSideButtons)
            Toggle("Command + X in Finder", isOn: $enableCommandX)
            
            Divider()
            
            Button("Open Privacy Settings…") {
                PermissionsManager.openPrivacySettings()
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
    let featureController = FeatureController()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
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
