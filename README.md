# Lofitime

**A little music. A little more focus.** A native macOS menu-bar app for lo-fi radio and Pomodoro timers, built with SwiftUI.

[Website](https://lofi.beffa.xyz) · [Download for Mac](https://github.com/t1llo/lofitime/releases/latest) · [Releases](https://github.com/t1llo/lofitime/releases)

## Install

[Download the latest release](https://github.com/t1llo/lofitime/releases/latest).

Requires **macOS 14 or later**. Open the DMG and drag **Lofitime.app** into **Applications**. Releases support Apple Silicon and Intel Macs and are signed and notarized.

## Screenshots

<img src="https://lofi.beffa.xyz/assets/studio-candlelight.webp" alt="Lofitime studio with a break timer and lo-fi music controls" width="700">

<img src="https://lofi.beffa.xyz/assets/menu-bar-candlelight.webp" alt="Lofitime's compact menu-bar timer and music player" width="320">

## Features

- Four live stations: Chill house, Study lo-fi, Sleepy lo-fi, and Synthwave.
- A compact studio and menu-bar panel with live video backgrounds and independent music controls.
- Customizable Pomodoro cycles, with default focus and break durations of 25 / 5 / 15 minutes.
- Editable countdowns: enter minutes (`45`) or minutes and seconds (`25:30`).
- An **80-day activity grid** with daily focus totals and session history.
- Candlelight and Catppuccin Mocha themes.
- Launch at login, completion notifications, chimes, and optional automatic session transitions.
- Automatic updates, configurable in Settings.

## Using Lofitime

Choose a station and press **Play music** to listen, or **Start focus** to begin a session. Music and timer controls work independently. Closing the studio keeps the app in your menu bar; choose **Open studio** to return.

Type a duration directly into the countdown and press Return or Start to apply it. Pause a running timer before editing its time. A custom duration applies to the current session; saved defaults are available in Settings.

Activity squares show completed focus sessions. Hover a square for its totals or click it to see that day's sessions. Older history is retained locally, along with your preferences and current timer. Skipped and reset sessions do not count as completed work.

Allow macOS notifications when prompted to receive completion alerts. Launch at login and notification preferences can be changed in Settings. Use **Check for Updates…** in the app menu or the panel's `…` menu to check for updates immediately.

Radio playback requires an internet connection. Connection errors include a retry control; the studio's video button opens the player for any YouTube prompts.

## Build from source

Requires **Swift 6+** and recent Apple Command Line Tools or Xcode. Swift Package Manager downloads dependencies on the first build.

```sh
xcode-select --install # If developer tools are not already installed
make run
```

The app is built at **`build/Lofitime.app`**. Local builds use an ad-hoc signature.

### Development commands

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

Tests run with Command Line Tools alone. Native smoke tests require an internet connection and a logged-in macOS desktop session, use isolated settings, and play briefly at 1% volume. Use `LOFI_BACKGROUND_SECONDS=360 make smoke` for a six-minute background-playback check.

Previews are saved to `build/previews/`. The activity example uses sample data without changing your session history.

## Keyboard shortcuts

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

## Third-party notices

See [ATTRIBUTION.md](ATTRIBUTION.md) for media ownership and dependency notices.
