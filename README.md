# Win Manager — consistent source replacement set

This ZIP is a *source patch*, not a complete `.xcodeproj`. It contains ten mutually aligned Swift files.

## Replace these existing files (do not add duplicate files to the target)

- `MyApp.swift`
- `EventTapController.swift`
- `FeatureController.swift`
- `ScrollReverseManager.swift`
- `SwitcherManager.swift`
- `AltTabOverlayView.swift`
- `PermissionsManager.swift`
- `WindowCloseManager.swift`
- `CommandXManager.swift`
- `DockManager.swift`
- `DisplayMoveManager.swift`
- `WindowCyclingManager.swift`

Back up or commit your current project first. Replace file contents in the existing Xcode target rather than adding a second same-named file. Do not add a `QuitProtectionManager.swift`; this app version intentionally has no Quit Protection feature. Keep exactly one `WindowCloseManager.swift` in the target.

## Requested menu

The menu is named **Win Manager** and contains features:
1. Quit on Close
2. Scroll Reverse (with Scroll Options submenu)
3. Cut & Paste (⌘X)
4. Dock Clicks (with Dock Options submenu: Sequential and All Windows)
5. App Switcher
6. Cycle Windows (⌘`)
7. Window Snapping
8. Display Switcher
9. Clean Mode

It uses exactly two dividers: after the app name and after the feature group. Clean Mode is the only feature disabled by default. It requires a confirmation dialog and automatically disables after 60 seconds.

In Xcode Target > Info, set **Bundle display name** to `Win Manager` if you also want Finder/System Settings to display that exact name.

## Window Snapping & Display Switching

Based on the window positioning and multi-display transfer algorithms from [Rectangle](https://github.com/rxhanson/Rectangle).

### Window Snapping (4 Layouts)
Uses <kbd>⌃ Control</kbd> + <kbd>⌥ Option</kbd> without Command or Shift:

| Action | Shortcut Keys | Description |
| :--- | :--- | :--- |
| **Left Half** | <kbd>⌃</kbd> + <kbd>⌥</kbd> + <kbd>←</kbd> | Snaps window to the left 50% of the display's usable frame |
| **Right Half** | <kbd>⌃</kbd> + <kbd>⌥</kbd> + <kbd>→</kbd> | Snaps window to the right 50% of the display's usable frame |
| **Full Screen** | <kbd>⌃</kbd> + <kbd>⌥</kbd> + <kbd>↩</kbd> *(or <kbd>⌃⌥↑</kbd>)* | Maximizes window across visible area (respecting menu bar & Dock) |
| **Default Size** | <kbd>⌃</kbd> + <kbd>⌥</kbd> + <kbd>C</kbd> *(or <kbd>⌃⌥↓</kbd>)* | Resizes to balanced dimensions (~70% width, ~80% height) and centers |

### Display Switching (Multi-Monitor Support)
Moves the frontmost window across connected displays while preserving edge alignments (e.g. snapped halves or maximized states) and proportional positioning:

| Action | Simplified Shortcut (3 Keys) | Legacy Shortcut |
| :--- | :--- | :--- |
| **Next Display** | <kbd>⌃</kbd> + <kbd>⌘</kbd> + <kbd>→</kbd> *(or <kbd>⌥⌘→</kbd>)* | <kbd>⌃</kbd> + <kbd>⌥</kbd> + <kbd>⌘</kbd> + <kbd>→</kbd> |
| **Previous Display** | <kbd>⌃</kbd> + <kbd>⌘</kbd> + <kbd>←</kbd> *(or <kbd>⌥⌘←</kbd>)* | <kbd>⌃</kbd> + <kbd>⌥</kbd> + <kbd>⌘</kbd> + <kbd>←</kbd> |

## App Switcher behavior

To list running regular applications without filtering hidden apps and to restore minimized windows, the switcher is a custom no-preview app list styled with Apple's `NSVisualEffectView` material. Apple does not expose a public API to customize the exact built-in macOS Cmd+Tab list. This custom panel takes over Cmd+Tab when enabled, includes minimized/hidden *regular* apps, and attempts to restore and raise a selected minimized window using Accessibility. Apps with accessory/background-only activation policy are not included, and apps may decline activation or expose incomplete Accessibility data.

## Scroll behavior

`Scroll Reverse` provides independent direction control for external mice and trackpads, matching the behavior of Pilotmoon Scroll-Reverser.
By default:
- **External Mice:** Reversed (classic Windows-style scrolling).
- **Trackpads:** Natural (untouched, with full gesture and momentum support).
- Additional preferences (`Reverse Mouse`, `Reverse Trackpad`, `Reverse Horizontal`) can be customized via the **Scroll Options** submenu under Scroll Reverse in the menu.

## Quit on Close

Uses Accessibility window notifications rather than polling. It attempts to terminate a regular app after a standard window was observed being destroyed and a successful follow-up query confirms no standard windows remain. Finder is excluded because it is the macOS shell. App-specific Accessibility limitations mean this feature is best-effort.

## Required permissions

- **Input Monitoring:** needed for global keyboard and scroll event tap.
- **Accessibility:** needed for window snapping, moving between displays, Dock detection, restoring minimized windows, and Quit on Close.

If permissions were previously denied, enable Win Manager under System Settings > Privacy & Security > Input Monitoring and Accessibility, then choose Refresh by relaunching/returning to the app as needed.

## Test checklist

1. Build the `WinManager` scheme.
2. Scroll vertically on a physical mouse; verify direction reverses. Test a trackpad too if available.
3. In Finder, select a file, press Cmd+X, open another folder, press Cmd+V; verify it moves.
4. Click the Dock icon of the active app with an unminimized window; it should minimize the focused window. Click a minimized app to let macOS restore it.
5. Press Cmd+Tab: a system-material app list should open. Confirm a minimized app appears, select it, and check that its window is restored when Accessibility is granted.
6. Test Window Snapping on active app:
   - Press <kbd>⌃⌥←</kbd> to snap left half.
   - Press <kbd>⌃⌥→</kbd> to snap right half.
   - Press <kbd>⌃⌥↩</kbd> to maximize window to full screen.
   - Press <kbd>⌃⌥C</kbd> to center window with default size.
7. Test Display Switcher with an external monitor connected:
   - Press <kbd>⌃⌘→</kbd> or <kbd>⌥⌘→</kbd> to transfer window to next display.
   - Press <kbd>⌃⌘←</kbd> or <kbd>⌥⌘←</kbd> to transfer window back to previous display.
8. Click Clean Mode; Cancel must leave input unchanged. Enable must block keyboard input and release automatically after 60 seconds; mouse should remain usable.
9. Close the last standard window in a test app with Quit on Close enabled; verify it exits. Be aware macOS apps vary in how they expose windows.

## Validation status

All files passed Swift syntax parsing and typechecking. This environment cannot perform an AppKit link/build or run the app on macOS, so the source still requires an Xcode build and runtime acceptance test on your Mac. Do not treat syntax parsing as proof that every runtime behavior is guaranteed.
