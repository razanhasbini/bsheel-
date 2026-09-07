# Dynamic Island / Live Activity setup

All the Swift, SwiftUI and Dart code is already in the repo. The one thing
this guide can't do for you is register the Widget Extension target with
Xcode — that's a click-through in the project settings. ~3 minutes.

## What's already wired

- `ios/QuestLiveActivity/QuestActivityAttributes.swift` — shared model.
- `ios/QuestLiveActivity/QuestLiveActivity.swift` — SwiftUI views (lock
  screen, Dynamic Island compact / expanded / minimal).
- `ios/QuestLiveActivity/Info.plist` — widget extension Info.plist.
- `ios/Runner/QuestLiveActivityChannel.swift` — `MethodChannel` bridge.
- `ios/Runner/AppDelegate.swift` — registers the channel on launch.
- `ios/Runner/Info.plist` — `NSSupportsLiveActivities = YES` set.
- `apps/mobile_app/lib/core/services/live_activity_service.dart` — Dart
  wrapper.
- `apps/mobile_app/lib/shared/navigation/bottom_nav_shell.dart` — listens
  to `activeQuestProvider` and calls start / update / end.

## What you have to do in Xcode

1. **Open the workspace** (not the .xcodeproj — the workspace):
   ```
   open apps/mobile_app/ios/Runner.xcworkspace
   ```

2. **Add a Widget Extension target.**
   - File → New → Target…
   - Pick **Widget Extension** under iOS.
   - Product Name: `QuestLiveActivity`
   - Bundle ID: `com.questapp.mobileApp.QuestLiveActivity` (Xcode
     usually auto-derives this from the parent app's bundle id).
   - Team: same team as Runner (`JMDKX9TYX6`).
   - **Tick "Include Live Activity"** when prompted.
   - Do **NOT** tick "Include Configuration Intent."
   - Activate the scheme when Xcode asks.

3. **Replace the auto-generated source files** with the ones already
   committed under `ios/QuestLiveActivity/`:
   - Right-click the new `QuestLiveActivity` group → Add Files to
     "Runner"… → select:
     - `QuestActivityAttributes.swift`
     - `QuestLiveActivity.swift`
     - `Info.plist` (set as the Info.plist for the target)
   - When prompted, make sure **only** the `QuestLiveActivity` target
     is ticked (NOT Runner) for each file.
   - Delete the placeholders Xcode generated (e.g. `QuestLiveActivityLiveActivity.swift`,
     `QuestLiveActivityBundle.swift`, the auto Attributes file). Keep
     only what's in `ios/QuestLiveActivity/`.

4. **Cross-add `QuestActivityAttributes.swift` to the Runner target.**
   The MethodChannel in Runner needs the same type the widget uses.
   - Select `QuestActivityAttributes.swift` in the Project navigator.
   - In the File inspector (right pane), under "Target Membership," tick
     **both** `Runner` and `QuestLiveActivity`.

5. **Set the widget target's iOS deployment target to 16.1.**
   - Select the `QuestLiveActivity` target.
   - Build Settings → iOS Deployment Target → 16.1.
   - The main Runner app stays at 13.0 — the Dart side already gates on
     `Platform.isIOS` and the native side gates on `@available(iOS 16.1)`.

6. **Build & run on a physical iPhone 14 Pro / 15 / 16 (Pro)**, on iOS
   16.1+. The simulator doesn't render the Dynamic Island; the Lock
   Screen view will work in the simulator if you lock the device.

## Verifying it works

1. Sign in.
2. Pick a quest.
3. Pull down the Notification Center / lock the phone → you'll see the
   quest card with a live ticking countdown.
4. Swipe away to home → the Dynamic Island pill at the top shows the
   flag glyph (leading) and the countdown (trailing).
5. Long-press the Dynamic Island → expanded view with title + XP reward.
6. Submit / cancel / let the quest expire → the activity disappears.

## Troubleshooting

- **"Activity didn't appear":** Settings → Bsheel → Live Activities. The
  user must have the system toggle on. The native side checks this and
  silently returns `"disabled"` if not.
- **Old activity still shows after kill+relaunch:** the Dart side wipes
  these on logout. To clean manually during dev: long-press the
  activity → swipe to dismiss.
- **"Use of unresolved identifier 'QuestActivityAttributes'":** the file
  isn't a member of the Runner target. See step 4 above.
- **Widget compiles but stays at "placeholder text":** ensure
  `QuestLiveActivityBundle` has `@main` — the file in this repo does, but
  if Xcode's generated file is still in the target the build will pick
  whichever sees `@main` last.
