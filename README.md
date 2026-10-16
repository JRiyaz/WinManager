# WinManager — macOS menu-bar utility

This is a cleaned-up replacement project for the supplied WinManager source. It keeps the existing feature set, removes the duplicate unused Settings view, avoids recurring window polling, and adds a confirmation-based Cleaning Mode.

## Features

- **App Switcher (⌘Tab):** a custom app-only switcher, ordered by activation history observed while WinManager is running. It is not a native-window preview switcher and does not promise identical behavior across Spaces/full-screen apps.
- **Dock Click to Minimize:** best-effort Accessibility-based detection of a click on the Dock icon of the app that is already frontmost. It only consumes the mouse-down/up pair after a successful minimize. Other Dock clicks remain native.
- **Quit on Last Window Close:** opt-in and disabled by default. Uses Accessibility notifications rather than a one-second polling timer. It can only work for apps/windows that expose the needed Accessibility notifications. It rechecks once after a short event-triggered grace period, does nothing on failed/unknown Accessibility queries, and excludes several system/developer apps.
- **Quit Protection (hold ⌘Q):** swallows the original shortcut and posts a tagged synthetic ⌘Q if the chord remains held for one second. Timing/shortcut behavior still needs real-device testing.
- **Reverse Conventional Mouse Wheel:** inverts the vertical scroll deltas for discrete wheel events. Continuous touch scrolling (trackpads and many Magic Mouse gestures) is left unchanged.
- **Finder Cut & Paste (⌘X to Move):** translates Finder ⌘X into copy, and the next file-compatible ⌘V into Finder's ⌘⌥V move command. It is a shortcut emulation, not a Finder API, and should be tested with the user's actual Finder workflow.
- **Cleaning Mode:** requires a confirmation dialog, blocks ordinary keyboard down/up and modifier events for up to 60 seconds, leaves mouse input available, and can be turned off from the menu at any time. It is a best-effort event-tap filter, not a hardware-level keyboard lock; secure/system-level input can be outside its control.

## Resource usage

There are no recurring polling timers. The global `CGEventTap` is event-driven and must remain available while global keyboard/mouse features are enabled. The app also uses lightweight Workspace notifications. Accessibility observers are installed only while **Quit on Last Window Close** is enabled. A one-shot timer exists only during the ⌘Q hold, and a one-shot timeout exists only during Cleaning Mode.

A strict claim of zero background work would be incompatible with global shortcuts and event interception. The intended idle behavior is no polling loop and no periodic wake-up task.

## Open and build

1. Open `WinManager.xcodeproj` in Xcode 27 (or a recent Xcode that supports the project format).
2. Select the **WinManager** scheme and **My Mac** destination.
3. Confirm the bundle identifier is `com.riyazjpersonalteam.WinManager` and select your own development team under Signing if Xcode reports a team/signing issue.
4. Build and run. The project is configured as a macOS-only app with a minimum deployment target of macOS 14.
5. Grant Accessibility and Input Monitoring when macOS requests them. If a global feature does not work, open the corresponding Privacy & Security pane, enable WinManager, then use **Refresh Permission Status** or **Retry Input Tap** in its menu.

## If macOS no longer shows a permission prompt

macOS remembers privacy choices and does not promise to show a dialog on every request. For development testing, quit the app and run these commands in Terminal:

```bash
tccutil reset Accessibility com.riyazjpersonalteam.WinManager
tccutil reset ListenEvent com.riyazjpersonalteam.WinManager
```

Then relaunch the app. If it still does not appear, verify the *built* app's bundle identifier and signature, manually add/enable the built `.app` in System Settings → Privacy & Security → Accessibility and Input Monitoring, and restart it. When running from Xcode, macOS may attribute the permission to a different executable/code identity than expected, so use the exact app build you intend to authorize.

The permission APIs used here ask macOS for authorization but cannot override a previous denial, bypass TCC, or guarantee the UI prompt appears. See Apple's documentation for [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) and [`CGRequestListenEventAccess`](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()).

## Manual acceptance test

Run these tests on the target macOS build before relying on the utility:

1. **First launch:** check Accessibility/Input Monitoring prompts and verify the menu correctly reports/retries an inactive input tap.
2. **App switcher:** open at least three regular apps; test ⌘Tab, ⇧⌘Tab, releasing Command to commit, hidden apps, minimized windows, full-screen apps, and multiple Spaces.
3. **Dock minimize:** click the Dock icon for the current frontmost app and confirm a standard window minimizes; click another app's icon and confirm normal activation remains intact.
4. **Auto-quit:** leave the feature off by default. When testing it, use a disposable app with one accessible window and verify closing its last window requests termination; also verify a failed AX query never terminates the app.
5. **Quit protection:** tap ⌘Q quickly (should cancel), hold ⌘Q longer than one second (should request quit), and release Command before Q.
6. **Scroll:** test a discrete-wheel USB/Bluetooth mouse and a trackpad separately. Trackpad/continuous scroll should remain unchanged.
7. **Finder cut/move:** select a test file, press ⌘X, navigate to another folder, press ⌘V, then verify the file moved. Also test Escape, regular ⌘C, a non-Finder app, and an empty/non-file clipboard.
8. **Cleaning Mode:** click **Cleaning Mode…**, cancel once, then confirm it. Verify ordinary typing and shortcuts are suppressed, mouse input still works, the menu can disable it, and it automatically unlocks after 60 seconds. Test starting/stopping while modifier keys are held.
9. **Idle behavior:** leave the app idle and inspect Activity Monitor/logs. There should be no repeating window polling timer; event-tap callbacks happen only when relevant system events occur.

## Verification status

The project file, XML/JSON resources, and Swift source syntax have been checked in the generation environment. This environment is not macOS and has no Xcode/AppKit SDK, so it cannot compile or run this project. Treat this as a complete source implementation prepared for Xcode validation, not a claim that a macOS runtime test or performance benchmark has already passed.