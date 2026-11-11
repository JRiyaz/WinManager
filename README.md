# Win Manager

**Bring familiar Windows-style window management and productivity shortcuts to macOS.**

Win Manager is a lightweight macOS menu bar utility that brings together window snapping, multi-display movement, app and window switching, mouse-scroll preferences, and other productivity features.

> **Note:** Win Manager relies on macOS Accessibility and Input Monitoring permissions for system-wide interactions. Some behavior is best-effort because macOS does not expose public APIs for every Dock, window, or system-switcher interaction.

## Features

### 1. Quit on Close
Automatically asks an application to quit after its last standard window is closed.

- Uses Accessibility window-destruction notifications rather than continuous polling.
- Checks that no standard windows remain before requesting termination.
- Excludes Finder because it is part of the macOS shell.
- Best-effort: applications differ in the window information they expose, and some intentionally remain open without windows.

### 2. Scroll Reverse
Configure scrolling direction independently for external mice and trackpads.

- **External mouse:** reversed by default for a Windows-style scrolling feel.
- **Trackpad:** natural scrolling by default; continuous gestures and momentum are left intact.
- **Reverse Mouse:** control mouse-wheel direction.
- **Reverse Trackpad:** control trackpad direction.
- **Reverse Horizontal:** optionally reverse horizontal scrolling.

The Scroll Options submenu lets you adjust behavior without changing the macOS-wide scrolling preference.

### 3. Cut & Paste (⌘X)
Adds a familiar cut-and-paste workflow for files in Finder.

- Select a file in Finder and press **⌘X**.
- Navigate to the destination folder and press **⌘V**.
- The selected item is moved to the destination.

This is intended for Finder file operations, not as a replacement for text editing's standard Cut command.

### 4. Dock Clicks
Change what happens when you click an application's Dock icon.

- Clicking the active app's Dock icon can minimize its focused window.
- Clicking another app or a minimized app is left to macOS so it can activate or restore that app.
- **Sequential** and **All Windows** options control how the feature handles an application's windows.

Dock accessibility information can vary between macOS versions, so Dock item detection is best-effort.

### 5. App Switcher
Use a custom app switcher with **⌘Tab**.

- Displays running regular applications in a custom panel using Apple's system visual-effect material.
- Supports forward and reverse cycling.
- Includes hidden and minimized regular applications.
- Attempts to restore and raise a selected minimized window using Accessibility.

Accessory and background-only apps are not included. macOS does not provide a public API to customize its built-in Cmd+Tab interface; Win Manager uses its own overlay and attempts to intercept the shortcut. System-reserved shortcut handling can vary by macOS version and configuration.

### 6. Cycle Windows (⌘`)
Cycle between windows of the current application using **⌘`**.

### 7. Window Snapping
Position the frontmost window using **Control (⌃) + Option (⌥)** shortcuts.

| Action | Shortcut | Result |
|---|---|---|
| Left Half | `⌃` + `⌥` + `←` | Fits the window to the left half of the usable display area |
| Right Half | `⌃` + `⌥` + `→` | Fits the window to the right half of the usable display area |
| Full Screen / Maximize | `⌃` + `⌥` + `↩` or `⌃` + `⌥` + `↑` | Expands the window across the visible display area |
| Default Size | `⌃` + `⌥` + `C` or `⌃` + `⌥` + `↓` | Resizes and centers the window (approximately 70% width and 80% height) |

Window positioning and multi-display transfer logic are based on ideas from [Rectangle](https://github.com/rxhanson/Rectangle).

### 8. Display Switcher
Move the frontmost window between connected displays while preserving relative placement and edge alignment where possible.

| Action | Shortcut | Result |
|---|---|---|
| Next Display | `⌃` + `⌘` + `→` or `⌥` + `⌘` + `→` | Moves the window to the next display |
| Previous Display | `⌃` + `⌘` + `←` or `⌥` + `⌘` + `←` | Moves the window to the previous display |

The transfer logic attempts to preserve snapped or maximized layouts and proportional positioning.

### 9. Clean Mode
Temporarily blocks keyboard input while leaving the mouse usable.

- Requires confirmation before activation.
- Automatically turns off after **60 seconds**.
- Disabled by default.
- Useful for temporarily preventing accidental keyboard input.

## Menu Bar
Win Manager runs as a menu bar utility. Its menu includes:

- Quit on Close
- Scroll Reverse and Scroll Options
- Cut & Paste
- Dock Clicks and Dock Options
- App Switcher
- Cycle Windows
- Window Snapping
- Display Switcher
- Clean Mode

## Permissions

| Permission | Used for |
|---|---|
| **Input Monitoring** | Listening for global keyboard shortcuts, mouse clicks, and scroll events |
| **Accessibility** | Reading and controlling supported application windows, snapping and moving windows, Dock interaction, restoring minimized windows, and Quit on Close |

To grant access:

1. Open **System Settings → Privacy & Security**.
2. Open **Input Monitoring** and enable Win Manager.
3. Open **Accessibility** and enable Win Manager.
4. If you have just changed permissions, quit and reopen Win Manager.

macOS may show different wording or require a relaunch depending on the OS version.

## Installation

1. Clone or download this repository.
2. Open `WinManager.xcodeproj` in Xcode.
3. Select the **WinManager** scheme and your Mac as the run destination.
4. Configure signing with your Apple Developer team if Xcode requires it.
5. Build and run the app.
6. Grant Input Monitoring and Accessibility permissions when prompted or from System Settings.

For a standalone copy, use **Product → Archive** in Xcode and follow the distribution flow appropriate for your build.

## macOS Compatibility and Limitations

- Win Manager is a regular user-session menu bar application, not a system daemon. It runs while the user is logged in and the app is running.
- Global event monitoring is subject to macOS privacy permissions and event-tap restrictions.
- Disabling App Sandbox does **not** bypass Accessibility or Input Monitoring protections.
- The built-in macOS app switcher is system-controlled. The custom switcher can only provide a best-effort replacement for its shortcut and presentation.
- Accessibility data and Dock structure differ between applications and macOS releases. Window movement, Dock hit-testing, minimized-window restoration, and Quit on Close may not work with every app.
- Applications can refuse activation, expose incomplete window data, or intentionally remain running without windows.
- Window snapping and display movement depend on the target application's support for Accessibility window positioning.

## Development Notes

- **Language:** Swift
- **UI:** SwiftUI / Menu Bar
- **System integration:** AppKit, Core Graphics event taps, and Accessibility APIs
- **Window layout inspiration:** [Rectangle](https://github.com/rxhanson/Rectangle)
- **Scroll behavior inspiration:** [Scroll Reverser](https://github.com/pilotmoon/scroll-reverser)

## Testing Checklist

- [ ] Test mouse and trackpad scrolling independently.
- [ ] Test all Scroll Options combinations, including horizontal scrolling.
- [ ] Test Finder Cut & Paste with files and folders.
- [ ] Test Dock clicks with active, inactive, and minimized applications.
- [ ] Test App Switcher forward and reverse cycling, including hidden and minimized apps.
- [ ] Test Cycle Windows with an app that has multiple windows.
- [ ] Test all four Window Snapping layouts.
- [ ] Test Display Switcher with two or more connected displays.
- [ ] Verify Clean Mode confirmation, keyboard blocking, and automatic 60-second timeout.
- [ ] Test Quit on Close with a disposable app that has no unsaved work.
- [ ] Re-test after revoking and re-granting privacy permissions and after sleep/wake.

## Acknowledgements

- [Rectangle](https://github.com/rxhanson/Rectangle) for window positioning and display-transfer inspiration.
- [Scroll Reverser](https://github.com/pilotmoon/scroll-reverser) for scroll-direction behavior inspiration.

---

**Win Manager** — practical Windows-style workflows for macOS.
