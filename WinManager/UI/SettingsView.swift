//
//  SettingsView.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("enableAppSwitcher") var enableAppSwitcher = false
    @AppStorage("enableWindowLayout") var enableWindowLayout = false
    @AppStorage("enableDockPreview") var enableDockPreview = false
    @AppStorage("enableDockClicks") var enableDockClicks = true
    @AppStorage("enableAutoQuit") var enableAutoQuit = true
    @AppStorage("enableQuitProtection") var enableQuitProtection = true
    @AppStorage("enableSideButtons") var enableSideButtons = false
    @AppStorage("enableCommandX") var enableCommandX = true

    var body: some View {
        Form {
            Section(header: Text("Window Management")) {
                Toggle("App Switcher (Live Previews)", isOn: $enableAppSwitcher)
                Toggle("Window Layouts (Snapping)", isOn: $enableWindowLayout)
            }
            Section(header: Text("Dock & Apps")) {
                Toggle("Dock Previews", isOn: $enableDockPreview)
                Toggle("Dock Clicks (Minimize/Hide)", isOn: $enableDockClicks)
                Toggle("Quit on Close", isOn: $enableAutoQuit)
                Toggle("Quit & Close Protection (Hold ⌘Q)", isOn: $enableQuitProtection)
            }
            Section(header: Text("System Utilities")) {
                Toggle("Mouse Side Buttons", isOn: $enableSideButtons)
                Toggle("Command + X in Finder", isOn: $enableCommandX)
            }
        }
        .padding(20)
        .frame(width: 350)
    }
}
