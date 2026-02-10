# PomodoroPlus

A full-featured macOS Pomodoro timer app designed for personal productivity. Features include a menu bar interface, full-screen break overlays, customizable sounds, multiple profiles, and comprehensive statistics tracking.

## Features

**Timer Management**: Start, pause, resume, and reset work sessions with configurable durations for work periods (default 25 minutes), short breaks (5 minutes), and long breaks (15 minutes). Long breaks occur automatically after every 4 work sessions.

**Break Overlay**: When a break begins, a full-screen overlay covers all connected monitors to encourage proper rest. The overlay operates in strict mode by default, preventing you from skipping breaks. Optional delayed-skip allows ending breaks after a configurable waiting period.

**Sound Notifications**: Per-event sound selection for work completion, break completion, and warning reminders. Supports importing custom MP3, M4A, and WAV audio files. All sounds play in-app with configurable duration and a stop button.

**System Notifications**: Banner notifications appear 1 minute before phase completion (configurable) and when phases end. Sound playback is handled separately from notifications to ensure consistent behavior.

**Multiple Profiles**: Create, duplicate, rename, and delete profiles. Each profile maintains its own timing rules, sound selections, overlay behavior, and feature settings. Reset any profile to base defaults with a single click.

**Statistics Tracking**: Session data is logged in JSONL format for easy analysis. View summaries for today, this week, and all time directly in the app. Statistics include completed sessions, total focus time, and skipped sessions.

**Global Hotkeys**: Control the timer from anywhere with keyboard shortcuts (Cmd+Shift+P to start/pause, Cmd+Shift+S to stop alarm, Cmd+Shift+K to skip phase). Requires Accessibility permissions.

## System Requirements

macOS 14.0 or later (adjust `MACOSX_DEPLOYMENT_TARGET` in the project for your macOS version).

## Installation

1. Open `PomodoroPlus.xcodeproj` in Xcode
2. Add sound files to the `Sounds` folder (see `Sounds/README.md` for details)
3. Build and run (Cmd+R)
4. Grant notification permissions when prompted
5. For global hotkeys, grant Accessibility permissions in System Settings > Privacy & Security > Accessibility

## Project Structure

```
PomodoroPlus/
├── PomodoroPlusApp.swift  # App entry point and delegate
├── AppHome.swift                  # Directory management
├── Models.swift                   # Data structures
├── SoundLibrary.swift             # Sound file management
├── ProfileStore.swift             # Profile CRUD operations
├── TimerEngine.swift              # Core timer state machine
├── AlarmPlayer.swift              # Audio playback
├── NotificationScheduler.swift    # System notifications
├── OverlayManager.swift           # Full-screen break overlay
├── HotkeyManager.swift            # Global keyboard shortcuts
├── StatsStore.swift               # Statistics logging
├── StatusBarController.swift      # Menu bar interface
├── SettingsView.swift             # Settings window
├── Assets.xcassets/               # App icons and colors
├── Sounds/                        # Bundled audio files
├── Info.plist                     # App configuration
└── PomodoroPlus.entitlements
```

## App Home Directory

The app stores all user data in `~/Library/Application Support/PomodoroPlus/`:

```
PomodoroPlus/
├── profiles/
│   ├── base_defaults.profile.json
│   └── default.profile.json
├── sounds/
│   ├── library.json
│   └── imported/
├── stats/
│   └── stats.jsonl
└── state/
    └── runtime_state.json
```

Open this folder from the app using "Open Folder" in the menu bar popover or from the Settings window.

## Usage

After launching, the app appears as a tomato emoji (🍅) in the menu bar. Click to access the popover interface where you can start/pause the timer, switch profiles, view quick stats, and access settings.

The Settings window (accessible via the popover) provides comprehensive configuration across eight tabs: Profiles, Timing, Sounds, Alerts, Break Overlay, Features, Hotkeys, and Stats.

When a work session ends, an alarm sound plays and the break overlay appears. During breaks, the overlay displays a countdown timer and (depending on settings) an "End Break" button. The overlay covers all screens to encourage proper rest.

## Customization

**Timing**: Adjust work and break durations in Settings > Timing. The classic Pomodoro technique uses 25-minute work sessions, but you can configure any duration from 1 to 120 minutes.

**Sounds**: Import custom audio files in Settings > Sounds. Select different sounds for work completion, break completion, and warning reminders. Test sounds before saving your selection.

**Overlay Behavior**: Configure strict mode and delayed skip in Settings > Break Overlay. Strict mode prevents skipping breaks entirely. Delayed skip shows a disabled button that becomes active after a configurable delay (default 30 seconds).

**Profiles**: Create separate profiles for different work contexts (e.g., "Deep Work" with 50-minute sessions, "Quick Tasks" with 15-minute sessions). Switch between profiles from the menu bar.

## Building for Distribution

For personal use, build and run directly from Xcode. For distribution:

1. Update the bundle identifier in the project settings
2. Configure code signing with your Apple Developer account
3. Archive the app (Product > Archive)
4. Notarize and staple for distribution outside the App Store

## License

This software is provided for personal use. Modify and distribute as needed for your own purposes.

## Troubleshooting

**Hotkeys not working**: Grant Accessibility permissions in System Settings > Privacy & Security > Accessibility. The app will prompt for this on first launch.

**No sound playing**: Ensure sound files exist in the Sounds folder. Check that the selected sound in Settings is valid. The app falls back to system beep if sounds are missing.

**Notifications not appearing**: Check notification permissions in System Settings > Notifications. Ensure "Banner Notifications" is enabled in Settings > Alerts.

**Overlay not covering all screens**: The overlay uses AppKit windows with `screenSaver` level. Some full-screen apps may interfere. Try running the other app in a window instead.
