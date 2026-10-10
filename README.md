# Lofitime

<img src="assets/icon.png" alt="Lofitime app icon" width="128">

[![Build](https://github.com/t1llo/lofitime/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/t1llo/lofitime/actions/workflows/build.yml)
[![Latest release](https://img.shields.io/github/v/release/t1llo/lofitime)](https://github.com/t1llo/lofitime/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-222222)

**A little music. A little more focus.** A native macOS menu-bar app for lo-fi radio and Pomodoro timers, built with SwiftUI.

[Website](https://lofi.beffa.xyz) · [Download for Mac](https://github.com/t1llo/lofitime/releases/latest)

## Install

Requires **macOS 14 or later**. Open the DMG and drag **Lofitime.app** into **Applications**. Releases support Apple Silicon and Intel Macs and are signed and notarized.

## Screenshots

<img src="https://lofi.beffa.xyz/assets/studio-candlelight.webp" alt="Lofitime studio with a break timer and lo-fi music controls" width="700">

<img src="https://lofi.beffa.xyz/assets/menu-bar-candlelight.webp" alt="Lofitime's compact menu-bar timer and music player" width="320">

## Features

- **Live lo-fi radio:** Chill house (default), Study lo-fi, Sleepy lo-fi, and Synthwave.
- **Headphone-aware playback:** music pauses when wired, Bluetooth, or USB headphones disconnect. Press Play to resume; your focus timer keeps running.
- **Focus timers:** customizable Pomodoro cycles and editable countdowns.
- **Your room:** a side-view 3D room with a desk, computer, window, and bed. Recent focus grows plants and flowers, fills bookshelves, and adds warm lamps, a reading nook, candles, keepsakes, and fairy lights. Scroll or pinch to zoom around the pointer, drag to move, Option-drag or right-drag to tilt, and double-click to reset the view.
- **A room that grows with you:** completed sessions nourish one shared room over the last seven days. Each session contributes fully for three days, then gently fades over the next four. After a week without focus the room returns to its essentials; your saved history and totals always remain.
- **A closer look at your focus:** choose **View stats** to zoom through the room's computer into a full-size statistics page. Explore weekly bars, monthly totals, active days, sessions, daily averages, and all-time focus. Click a day for its sessions, then **Back to room** to zoom back out to your previous view. Everything stays saved locally.
- **A room in your menu bar:** one button switches between music/timer controls and your cozy room, with quick timer and music controls. Your chosen view is remembered.
- **Native macOS:** a full-width room with compact bottom navigation, a menu-bar player, completion notifications, and five coordinated themes: Candlelight, Catppuccin, Moss, Moonlight, and Rosewood. The in-app logo and running Dock icon follow your theme.
- **Convenience:** launch at login, automatic updates, and optional automatic breaks.
- **Sync across Macs:** opt-in GitHub sync uses your GitHub CLI login and a private repository. Completed focus sessions merge across computers, keeping your room and statistics together without double-counting.
- **Video quality:** choose an available resolution through YouTube's player in Settings.

## Using Lofitime

In the menu-bar popup, choose a station and press **Play music**, or **Start focus** to begin a timer. Use the house/headphones button to switch to your room and back. Music and timers work independently; closing the app window keeps Lofitime in your menu bar.

Enter `45` or `25:30` into a paused countdown to change its duration. Open **Activity** for completed sessions and **Settings** for timer defaults, themes, and startup preferences. Radio playback requires an internet connection.

### Sync across Macs

1. Install [GitHub CLI](https://cli.github.com) on each Mac and sign in with `gh auth login --hostname github.com --web --scopes repo`.
2. In **Settings → Sync across Macs**, choose **Create a new sync**, enter a repository name (default: `lofitime-sync`), and choose **Create private sync**. Lofitime creates it under your active github.com account.
3. Choose **Copy repository link**. On another Mac, choose **Connect to sync**, paste that link, and click **Connect**. Existing histories are merged automatically. The GitHub account on each Mac must have write access to the private repository.

Connecting accepts a GitHub HTTPS repository link, an SSH clone URL, or `owner/repository`. It never creates a missing repository. You can also connect an empty private repository you already own.

Lofitime syncs at launch, when you return to the app, after every completed focus session, and every five minutes. **Sync now** refreshes immediately. Offline sessions stay saved locally and are retried automatically. Sessions keep their unique IDs, so repeated syncs and simultaneous updates from two Macs don't double-count time or overwrite each other's work.

The private repository stores `lofitime-sessions.json`: completed session IDs, completion dates, durations, and intentions. Your room and statistics are rebuilt from that shared history. Timer state, music, preferences, and GitHub credentials stay on each Mac. GitHub CLI manages authentication; Lofitime does not store tokens. The sync file is versioned JSON with native Swift date values (seconds since January 1, 2001 UTC).

**Disconnect** stops syncing on this Mac and keeps both your local history and the repository. Sync requires a private, writable repository; an existing repository must be empty or already contain Lofitime sync history.

## Build from source

Requires **Swift 6+** and recent Apple Command Line Tools or Xcode. Swift Package Manager downloads dependencies on the first build.

```sh
xcode-select --install # If developer tools are not already installed
make run
```

The app is built at **`build/Lofitime.app`**. Local builds use an ad-hoc signature.

| Command | What it does |
| --- | --- |
| `make check` | Test, build, and verify the app bundle |
| `make dev` | Launch a debug build |
| `make smoke` | Check native controls and live playback |
| `make activity-smoke` | Check room growth, weekly/monthly history, themes, and saved sessions offline |
| `make activity-preview` | Render all room stages and activity themes offline |
| `make audio-smoke` | Simulate headphone loss during live playback and check pause/resume |
| `make preview` | Save screenshots to `build/previews/` |
| `make help` | List commands |

GitHub Actions checks builds and scans Git history with Gitleaks on every push and pull request. Native smoke tests use isolated settings and require a logged-in desktop session. The playback smoke test also requires internet and plays briefly at 1% volume.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘ Return` | Start / pause / resume the timer |
| `⌘ ⇧ P` | Play / pause music |
| `⌘ ⇧ R` | Reset the current session |
| `⌘ 1` | Open your room |
| `⌘ 2` | View activity |
| `⌘ ,` | Open settings |
| `⌘ Q` | Quit |

With the room focused, use `+` / `−` to zoom, arrow keys to move, Option-arrow keys to tilt, and `0` to reset.

## Third-party notices

See [ATTRIBUTION.md](ATTRIBUTION.md) for media ownership and dependency notices.
