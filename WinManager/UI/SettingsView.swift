//
//  SettingsView.swift
//  WinManager
//
//  Created by Riyaz J on 16-10-2026.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("enableAppSwitcher") var enableAppSwitcher = false
    @AppStorage("enableDockClicks") var enableDockClicks = true
    @AppStorage("enableAutoQuit") var enableAutoQuit = true
    @AppStorage("enableQuitProtection") var enableQuitProtection = true
    @AppStorage("enableScrollReverse") var enableScrollReverse = true
    @AppStorage("enableCommandX") var enableCommandX = true

    var body: some View {
        Form {
            Section(header: Text("Window Management")) {
                Toggle("App Switcher (⌘Tab)", isOn: $enableAppSwitcher)
            }
            Section(header: Text("Dock & Apps")) {
                Toggle("Dock Click to Minimize", isOn: $enableDockClicks)
                Toggle("Quit on Last Window Close", isOn: $enableAutoQuit)
                Toggle("Quit Protection (Hold ⌘Q)", isOn: $enableQuitProtection)
            }
            Section(header: Text("System Utilities")) {
                Toggle("Scroll Reverse (External Mouse)", isOn: $enableScrollReverse)
                Toggle("Command + X in Finder", isOn: $enableCommandX)
            }
        }
        .padding(20)
        .frame(width: 350)
    }
}

