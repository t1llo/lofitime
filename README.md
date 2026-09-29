# Lofitime

A native **macOS menu-bar app** for lo-fi music and focus timers, built with SwiftUI.

## Start here

Requires **macOS 14+** and **Swift 6+** (recent Apple Command Line Tools or Xcode). Swift Package Manager fetches the pinned Sparkle 2.10.0 updater on the first build.

```sh
# If Apple's developer tools aren't installed yet:
xcode-select --install

# Build the app and launch it:
make run
```

The app is created at **`build/Lofitime.app`**. You can also double-click it in Finder. Local builds include artwork, the embedded player, Sparkle, a generated app icon, and an ad-hoc signature. Published downloads use Developer ID signing and Apple notarization.

## App updates

Install **Lofitime.app** from a signed release into Applications. It checks for updates every hour and automatically downloads verified updates, which install when the app quits. Sparkle can also offer **Install and Relaunch**. Use **Check for Updates…** in the app menu or the panel's `…` menu to check immediately; automatic checking and installation can be changed in Settings.

Update archives and feeds are EdDSA-signed, and apps are Developer ID-signed and notarized. The app contains only the public verification key. The feed is `https://github.com/t1llo/lofitime/releases/latest/download/appcast.xml`; automatic downloads work once this repository is public. Install an updater-enabled release once if you are upgrading from the original release without Sparkle.

## Your little studio

- **Four live genres** from Lofi Girl: Chill house (the default), Study lo-fi, Sleepy lo-fi, and Synthwave. Streamed inside the app using the official YouTube player; select a genre from the dropdown at the top. Your last selection is remembered.
- **A compact 700 × 540 studio** with a sidebar for Studio, Activity, and Settings.
- **A 320 × 360 menu-bar panel** with a darker backdrop, bolder countdown, and a simple station selector above music, volume, and timer controls.
- **Dimmed live video backgrounds** in the studio and menu-bar panel, with high-contrast controls over the stream and YouTube's title/controls cropped out. Paused or loading streams show station artwork. The same player moves between windows without restarting playback.
- **Soft, rounded typography** throughout the interface and countdown, with a clean, underline-free timer.
- **Settings inside the menu-bar panel**: use the sliders icon to edit saved focus/break lengths, cycle length, automatic breaks, music behavior, and theme.
- **Pomodoro sessions** with customizable focus, short-break, and long-break durations. Defaults: 25 / 5 / 15 minutes, with a longer break every four completed focus sessions.
- **Candlelight** by default: warm charcoal, cream, amber, and muted sage, with **Catppuccin Mocha** available in Settings. The selection applies to the app and menu-bar panel and is saved between launches. Previous Tokyo Night preferences migrate to Candlelight.
- **GitHub-style focus activity**: the last 80 days of completed sessions, with larger day squares and intensity based on focused time. Hover a square for totals or click it to see that day's sessions. Older session history stays saved.
- **Exact timer entry**: type minutes (`45`) or minutes and seconds (`25:30`) directly into the countdown. Press Return or Start to apply it. Pause a running timer to edit its time.
- **Launch at login** is enabled on the first normal launch and can be changed in Settings. Later launches respect your choice in macOS Login Items.
- **Session notifications**: the app asks for macOS notification permission on its first normal launch. Choose **Allow** for focus/break completion banners; change the preference in Settings, with a shortcut to macOS notification settings if permission was denied.
- Optional automatic session transitions, music when focusing, and completion chimes.

Click play to just listen, or **Start focus** to begin a session. Closing the studio keeps the app and music in your menu bar. Use **Open studio** to bring it back, or choose **Quit Lofitime** from the panel's `…` menu.

The timer uses a deadline rather than subtracting seconds, so it stays accurate when the app is hidden or the Mac sleeps. Active sessions, preferences, and completed-session history are stored locally. Music starts only when you ask it to. A skipped or reset session doesn't count toward your focus history.

While listening, the player keeps background stream processing active and checks playback every five seconds. Unexpected pauses resume automatically; stalled streams reconnect after 30 seconds without progress. Pausing music yourself stops recovery and releases the background activity.

A duration entered through the countdown applies to that session. Reset keeps your chosen duration; the next focus/break uses its saved default. Changing a paused duration starts it over. You can add an optional session name at the bottom of the studio. In Settings or the menu-bar settings panel, type a default duration and press Return or leave the field to save it.

Click the genre name to switch streams. The round music button plays/pauses the radio independently of the timer. The studio's video icon opens the uncropped video with the app's playback controls below it; **Back to timer** restores the overlay.

## Build and test

| Command | What it does |
| --- | --- |
| `make run` | Release-build, restart the running app, and open it |
| `make build` | Create `build/Lofitime.app` |
| `make dev` | Build and launch a debug app |
| `make test` | Run deterministic timer, activity, and preference-migration tests |
| `make check` | Run tests, release-build, and verify the signature and bundle resources |
| `make smoke` | Run the native app against all four real YouTube streams |
| `make preview` | Render native screenshots to `build/previews/` |
| `make install` | Copy the release app into `~/Applications` |
| `make clean` | Remove generated files |
| `make help` | List commands |

`make test` uses a dependency-free Swift executable so it works with Command Line Tools alone, including installations without XCTest. It checks timer transitions, exact duration parsing, persistence, activity aggregation, local-day/DST boundaries, and migration of existing preferences to the new themes. Failed checks exit with a nonzero status.

`make smoke` requires an internet connection and a logged-in macOS desktop session. It verifies real sidebar clicks, Activity session display and day filtering, native countdown editing and its keyboard shortcut, actual YouTube playback, video handoff between the studio and menu-bar panel, native pause, background playback, unexpected-pause recovery, changing stations with the window closed, and reopening the studio. Navigation is checked both before and during playback. It uses isolated app settings and plays at **1% volume** for background checks; WebKit intentionally suspends muted autoplay in hidden windows. Use `LOFI_BACKGROUND_SECONDS=360 make smoke` for a six-minute background-playback check. The smoke-test process exits automatically.

`make preview` briefly opens native windows and captures their content, including AppKit controls, without requesting screen-recording access. It includes both themes, the menu-bar timer settings, and an explicitly labeled activity example using sample data. Sample data is only used for that preview; it is never added to your history. Diagnostic commands are available only in debug builds.

### Try a complete Pomodoro

1. Type `0:10` directly into the countdown for a quick ten-second test.
2. Choose **Start focus** (or press **⌘ Return**) to apply the time and begin.
3. Close the window and open the waveform icon in your menu bar.
4. Pause/resume the timer and music independently, then let the session finish.
5. Open **Activity** to see today's square and the completed session. Click the square to filter the session list.

### Keyboard shortcuts

When Lofitime is the active app:

| Shortcut | Action |
| --- | --- |
| `⌘ Return` | Start / pause / resume the timer |
| `⌘ ⇧ P` | Play / pause music |
| `⌘ ⇧ R` | Reset the current session |
| `⌘ 1` | Open the studio |
| `⌘ 2` | View activity |
| `⌘ ,` | Open settings |
| `⌘ Q` | Quit |

## Project map

```text
Sources/LofiMenCore/        Timer, duration parsing, activity aggregation, preferences
Sources/LofiMen/            Shared app state, radio service, app lifecycle
Sources/LofiMen/Views/      Native studio, menu-bar panel, history, preferences
Sources/LofiMen/Resources/  YouTube bridge and bundled station artwork
Tests/LofiMenCoreTests/     Deterministic core test runner
scripts/                   App bundling, launch, and icon generation
Configuration/Info.plist    macOS app metadata
```

Open `Package.swift` in Xcode to explore the project, or edit it in any editor and use the Makefile. `make build CONFIGURATION=debug` also selects a debug bundle explicitly.

## Radio and artwork

Playback needs an internet connection. YouTube may present its normal player prompts; use the studio's video icon to access them. Connection failures appear in both the studio and menu-bar panel with a retry control.

The station IDs in `Sources/LofiMen/RadioPlayer.swift` were checked against Lofi Girl's live channel on September 29, 2026. If Lofi Girl replaces a stream, update the corresponding `RadioStation.videoID` there and rebuild. The player supplies a stable app referrer and uses load-specific message IDs so a previous station's delayed events cannot pause the next one.

Music and station artwork belong to **[Lofi Girl](https://www.youtube.com/@LofiGirl)**. See [ATTRIBUTION.md](ATTRIBUTION.md). Lofitime is an independent project. Sparkle's license is included in the app's Resources directory.
