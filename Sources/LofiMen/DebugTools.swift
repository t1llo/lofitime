import AppKit
import Observation
import os
import LofiMenCore
import SwiftUI
import SceneKit
import WebKit

/// Opt-in diagnostics are compiled only into debug builds. They use isolated timer storage.
enum DebugTools {
    @MainActor private static var hasRun = false

    static var requested: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--render-preview") || CommandLine.arguments.contains("--smoke-test")
            || CommandLine.arguments.contains("--performance-test") || CommandLine.arguments.contains("--smoke-activity")
            || CommandLine.arguments.contains("--smoke-audio-output")
            || CommandLine.arguments.contains("--render-activity")
        #else
        false
        #endif
    }

    @MainActor static func makeModel() -> AppModel {
        if requested, let defaults = UserDefaults(suiteName: "com.lofimen.diagnostics") {
            defaults.removePersistentDomain(forName: "com.lofimen.diagnostics")
            return AppModel(defaults: defaults)
        }
        return AppModel()
    }

    @MainActor static func prepareLaunch() {
        #if DEBUG
        guard requested else { return }
        // SwiftUI can restore a menu-bar-only launch after the previous window was closed.
            // Diagnostics need a window even in that case, before its .task can run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard !hasRun else { return }
            if let window = NSApp.windows.first(where: { $0.title == "Lofitime" }) {
                window.makeKeyAndOrderFront(nil)
            } else if let menu = NSApp.mainMenu?.items.compactMap(\.submenu).first(where: {
                $0.items.contains(where: { $0.title == "Open My Room" })
            }), let index = menu.items.firstIndex(where: { $0.title == "Open My Room" }) {
                menu.performActionForItem(at: index)
            } else {
                smokeFailure("Could not open the studio for native diagnostics")
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        #endif
    }

    @MainActor static func runIfRequested(model: AppModel) {
        #if DEBUG
        guard requested, !hasRun else { return }
        hasRun = true
        if let index = CommandLine.arguments.firstIndex(of: "--render-activity"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for appearance in AppAppearance.allCases {
                        try await renderActivityExample(to: directory.appendingPathComponent("activity-\(appearance.rawValue).png"), appearance: appearance)
                    }
                    try await renderActivityExample(to: directory.appendingPathComponent("activity-compact.png"), appearance: .candlelight,
                                                    size: CGSize(width: 700, height: 540))
                    try await renderActivityExample(to: directory.appendingPathComponent("activity-desktop.png"), appearance: .candlelight,
                                                    size: CGSize(width: 700, height: 540), showStats: true)
                    try await renderActivityExample(to: directory.appendingPathComponent("activity-stats-small.png"), appearance: .candlelight,
                                                    size: CGSize(width: 660, height: 500), showStats: true)
                    for minutes in [0, 25, 120, 360, 720] {
                        let now = Date()
                        let records = [SessionRecord(finishedAt: now, duration: Double(minutes) * 60, intention: "Preview")]
                        try await render(StudyRoomView(growth: FocusRoom(records: records, through: now))
                            .frame(width: 800, height: 580).environment(\.roomTheme, .candlelight)
                            .foregroundStyle(RoomTheme.candlelight.text).preferredColorScheme(.dark),
                            to: directory.appendingPathComponent("room-\(minutes).png"))
                    }
                    print("Activity previews saved to \(directory.path)")
                    exit(0)
                } catch { smokeFailure("Activity preview: \(error)") }
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for section in StudioSection.allCases {
                        model.section = section
                        try await render(StudioView(model: model).frame(width: 700, height: 540),
                                    to: directory.appendingPathComponent("\(section == .sessions ? "sessions" : "preferences").png"))
                    }
                    try await render(MenuBarView(model: model), to: directory.appendingPathComponent("menu-bar.png"))
                    model.section = .sessions
                    for station in [RadioStation.sleepy, .house] {
                        model.player.select(station)
                        try await render(MenuBarView(model: model), to: directory.appendingPathComponent("menu-bar-\(station.rawValue).png"))
                    }
                    if model.player.station != .defaultStation { model.player.select(.defaultStation) }
                    for appearance in AppAppearance.allCases {
                        model.preferences.appearance = appearance
                        model.section = .sessions
                        try await render(StudioView(model: model).frame(width: 700, height: 540),
                                         to: directory.appendingPathComponent("room-\(appearance.rawValue).png"))
                        try await render(MenuBarView(model: model), to: directory.appendingPathComponent("menu-bar-\(appearance.rawValue).png"))
                        model.section = .settings
                        try await render(StudioView(model: model).frame(width: 700, height: 540),
                                         to: directory.appendingPathComponent("preferences-\(appearance.rawValue).png"))
                        try await renderActivityExample(to: directory.appendingPathComponent("activity-\(appearance.rawValue).png"), appearance: appearance)
                    }
                    print("Native previews saved to \(directory.path)")
                    exit(0)
                } catch {
                    fputs("Preview failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        } else if CommandLine.arguments.contains("--smoke-audio-output") {
            Task { @MainActor in await smokeAudioOutput(model) }
        } else if CommandLine.arguments.contains("--performance-test") {
            Task { @MainActor in await smokePerformance(model) }
        } else if CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--smoke-activity") {
            Task { @MainActor in await smoke(model) }
        }
        #endif
    }

    #if DEBUG
    @MainActor private static func render<V: View>(_ view: V, to url: URL,
                                                 prepare: ((NSWindow) async -> Void)? = nil) async throws {
        // NSHostingView also captures native controls and scroll views, unlike ImageRenderer.
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(600))
        if let prepare {
            await prepare(window)
            try await Task.sleep(for: .milliseconds(800))
        }
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "LofiMen.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render native view"])
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        // Metal-backed SceneKit views need their renderer's snapshot; AppKit's
        // bitmap cache does not capture the GPU surface.
        func captureScenes(in view: NSView) {
            if let sceneView = view as? SCNView {
                let frame = hosting.convert(sceneView.bounds, from: sceneView)
                let rect = NSRect(x: frame.minX, y: hosting.isFlipped ? hosting.bounds.height - frame.maxY : frame.minY,
                                  width: frame.width, height: frame.height)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).addClip()
                sceneView.snapshot().draw(in: rect)
                if let desktop = (sceneView as? StudyRoomScene.RoomView)?.desktopHost, !desktop.isHidden,
                   let overlay = desktop.bitmapImageRepForCachingDisplay(in: desktop.bounds) {
                    desktop.cacheDisplay(in: desktop.bounds, to: overlay)
                    let screen = hosting.convert(desktop.bounds, from: desktop)
                    overlay.draw(in: NSRect(x: screen.minX, y: hosting.isFlipped ? hosting.bounds.height - screen.maxY : screen.minY,
                                           width: screen.width, height: screen.height))
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            view.subviews.forEach { captureScenes(in: $0) }
        }
        captureScenes(in: hosting)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LofiMen.Preview", code: 2)
        }
        try data.write(to: url)
    }

    @MainActor private static func smokeAudioOutput(_ model: AppModel) async {
        let player = model.player
        player.audioOutputDidDisconnect()
        guard !player.hasLoaded, !player.pausedForOutputChange else {
            smokeFailure("An idle output change loaded the radio"); return
        }
        model.preferences.startMusicWithFocus = false
        model.preferences.completionSound = false
        model.setDuration(600)
        model.toggleTimer()
        player.volume = 0
        player.play()
        player.audioOutputDidDisconnect()
        guard player.pausedForOutputChange, !player.isLoading, !player.isPlaying else {
            smokeFailure("Headphone loss did not cancel pending playback"); return
        }
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(500))
            if player.isReady { break }
            if player.error != nil { break }
        }
        guard player.isReady, !player.isPlaying else {
            smokeFailure("A radio that lost its output while loading failed to stay paused: \(player.error ?? "not ready")"); return
        }
        print("PASS: disconnect during loading stays paused when YouTube becomes ready")
        func resume() async -> Bool {
            player.play()
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(500))
                if player.isPlaying { return true }
                if player.error != nil { return false }
            }
            return false
        }
        guard await resume(), let window = NSApp.windows.first(where: { $0.title == "Lofitime" }) else {
            smokeFailure("Radio could not resume for the output test: \(player.error ?? "not playing")"); return
        }
        player.volume = 0.01
        window.orderOut(nil)
        player.audioOutputDidDisconnect()
        player.playWithFocus()
        // Exercise both a late iframe event and an attempted background restart.
        _ = try? await player.webView.evaluateJavaScript("send('state', 1); radioPlay()")
        try? await Task.sleep(for: .seconds(6))
        let state = try? await player.webView.evaluateJavaScript("player.getPlayerState()") as? Int
        guard player.pausedForOutputChange, !player.isPlaying, !player.isLoading,
              let state, state != 1 && state != 3, model.timer.status == .running else {
            smokeFailure("Playback restarted after headphone loss, or the focus timer stopped"); return
        }
        print("PASS: hidden-window playback pauses and stays paused through stale events, focus starts, and a recovery-monitor interval")
        window.makeKeyAndOrderFront(nil)
        player.volume = 0
        let station = player.station
        player.select(station == .house ? .lofi : .house)
        player.select(station)
        guard await resume(), !player.pausedForOutputChange else {
            smokeFailure("Explicit Play did not release media suspension after a station change"); return
        }
        player.pause()
        model.resetTimer()
        print("PASS: explicit Play resumes music after disconnect and station changes")
        print("Native audio-output smoke test passed.")
        exit(0)
    }

    /// Isolates background resource checks from other stations' availability and quality menus.
    @MainActor private static func smokePerformance(_ model: AppModel) async {
        let idleTime = model.now
        try? await Task.sleep(for: .seconds(2))
        guard model.now == idleTime, !model.player.hasLoaded else {
            smokeFailure("Idle app polled or loaded the player"); return
        }
        let panel = menuBarPanel(model)
        model.menuBarShowsRoom = true
        panel.orderFront(nil)
        defer { panel.close() }
        func startPlayback() async -> Bool {
            model.player.volume = 0.01
            model.player.play()
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(500))
                if model.player.isPlaying { model.player.volume = 0.01; return true }
                if model.player.error != nil { return false }
            }
            return false
        }
        guard await startPlayback(), let window = NSApp.windows.first(where: { $0.title == "Lofitime" }) else {
            smokeFailure("Performance test could not start radio: \(model.player.error ?? "no playing state")"); return
        }
        window.orderOut(nil)
        panel.orderOut(nil)
        try? await Task.sleep(for: .seconds(1))
        let start = try? await model.player.webView.evaluateJavaScript("player.getCurrentTime()") as? Double
        try? await Task.sleep(for: .seconds(6))
        let end = try? await model.player.webView.evaluateJavaScript("player.getCurrentTime()") as? Double
        guard let start, let end, end - start >= 5, model.player.isPlaying,
              !model.player.surfaces.isVideoVisible,
              model.player.webView.frame.size == CGSize(width: 320, height: 180) else {
            smokeFailure("Background playback or reduced video surface failed"); return
        }
        print("PASS: audio advances with the window hidden and the video surface reduced")
        fflush(stdout)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.menuBarShowsRoom = false
        panel.orderFront(nil)
        try? await Task.sleep(for: .seconds(1))
        guard model.player.surfaces.isVideoVisible, model.player.webView.frame.width > 320 else {
            smokeFailure("Visible video size did not recover"); return
        }
        model.player.pause()
        try? await Task.sleep(for: .seconds(6))
        guard !model.player.isPlaying, model.now == idleTime else {
            smokeFailure("Paused radio resumed or idle timer kept polling"); return
        }
        guard await startPlayback() else { smokeFailure("Radio did not resume after pausing"); return }
        model.player.pause()
        print("PASS: idle timer sleeps and radio pauses and resumes")
        exit(0)
    }

    @MainActor private static func smoke(_ model: AppModel) async {
        let idleTime = model.now
        try? await Task.sleep(for: .milliseconds(1_200))
        guard model.now == idleTime, !model.player.hasLoaded else {
            smokeFailure("An idle app refreshed its countdown or loaded the player"); return
        }
        print("PASS: idle timer does not poll and radio stays unloaded before first play")
        let labelSizes = ["00:00", "01:11", "09:59", "10:00", "59:59", "180:00"].flatMap { text in
            [false, true].map { MenuBarLabel.image(countdown: text, paused: $0).size }
        }
        guard MenuBarLabel.activeSize.width < 65,
              labelSizes.allSatisfy({ $0 == MenuBarLabel.activeSize }) else {
            smokeFailure("Menu-bar countdown width changes with digits or pause state"); return
        }
        let studioVideo = VideoGeometry.frame(in: MenuBarView.size, fill: true, focalPoint: 0.5)
        let menuVideo = VideoGeometry.frame(in: MenuBarView.size, fill: true, focalPoint: 0.5, presentation: .menuBar)
        guard menuVideo.height > studioVideo.height,
              menuVideo.minY < (MenuBarView.size.height - menuVideo.height) / 2,
              menuVideo.maxY > MenuBarView.size.height else {
            smokeFailure("Menu-bar video does not overscan the panel edges"); return
        }
        print("PASS: menu-bar countdown has fixed width across digits and pause states; preview overscans its edges")
        model.preferences.startMusicWithFocus = false
        model.setDuration(1_530)
        model.preferences.appearance = .catppuccin
        guard model.remainingText == "25:30" else { smokeFailure("Changing themes reset the custom duration"); return }
        model.preferences.appearance = .candlelight
        model.resetTimer()
        guard model.remainingText == "25:30" else { smokeFailure("Reset did not preserve the exact duration"); return }
        print("PASS: exact duration and theme changes preserve the timer")
        model.toggleTimer()
        guard model.timer.status == .running else { smokeFailure("Timer did not start"); return }
        let timerInvalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = model.timer.status } onChange: { timerInvalidated.withLock { $0 = true } }
        model.tick()
        guard !timerInvalidated.withLock({ $0 }) else {
            smokeFailure("A countdown tick invalidated unchanged timer state"); return
        }
        model.toggleTimer()
        guard model.timer.status == .paused else { smokeFailure("Timer did not pause"); return }
        model.selectMode(.shortBreak)
        guard model.remainingText == "05:00" else { smokeFailure("Mode selection did not reset the clock"); return }
        print("PASS: native timer start, pause, and mode selection")

        model.preferences.completionSound = false
        model.selectMode(.focus)
        model.setDuration(1)
        model.toggleTimer()
        try? await Task.sleep(for: .milliseconds(1_200))
        model.tick()
        guard model.records.count == 1, model.records.first?.duration == 1,
              model.activity.week.totalSessions == 1, model.activity.week.activeDays == 1,
              model.todayRecords.count == 1, model.todayDuration == 1 else {
            smokeFailure("A completed exact-duration session did not update activity")
            return
        }
        guard FocusRoom(records: model.records, through: model.activity.updatedAt).nourishment == 1 else {
            smokeFailure("A short completed session did not nourish the room"); return
        }
        smokeRoomModels()

        model.selectMode(.focus)
        model.banner = nil
        await smokeNavigation(model)
        let timerPanel = menuBarPanel(model)
        timerPanel.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        let window = timerPanel
        if let field = textFields(in: window.contentView).first(where: { $0.stringValue == "25:00" }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(for: .milliseconds(300))
            field.selectText(nil)
            try? await Task.sleep(for: .milliseconds(100))
            guard let editor = field.currentEditor() as? NSTextView else {
                smokeFailure("The countdown could not be edited"); return
            }
            editor.insertText("25:30", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            try? await Task.sleep(for: .milliseconds(100))
            editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
            try? await Task.sleep(for: .milliseconds(100))
            guard model.remainingText == "25:30" else {
                smokeFailure("Return did not apply the typed countdown (field: \(field.stringValue), editor: \(editor.string), draft: \(String(describing: model.durationInput)), timer: \(model.remainingText))"); return
            }
            print("PASS: typing mm:ss directly into the native countdown applies it on Return")
            field.selectText(nil)
            guard let minutesEditor = field.currentEditor() as? NSTextView else {
                smokeFailure("The countdown could not be edited again"); return
            }
            minutesEditor.insertText("45", replacementRange: NSRange(location: 0, length: minutesEditor.string.utf16.count))
            try? await Task.sleep(for: .milliseconds(100))
            guard let shortcut = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36),
                NSApp.mainMenu?.performKeyEquivalent(with: shortcut) == true else {
                smokeFailure("The timer keyboard shortcut was unavailable"); return
            }
            try? await Task.sleep(for: .milliseconds(100))
            guard model.timer.status == .running, model.timer.duration == 2_700 else {
                smokeFailure("Command-Return did not start the newly typed duration (duration: \(model.timer.duration), status: \(model.timer.status))"); return
            }
            model.resetTimer()
            print("PASS: Command-Return commits a newly typed duration before starting")
        } else {
            smokeFailure("The editable countdown is missing from the menu-bar popup"); return
        }

        await smokeMenuBarRoom(model, panel: timerPanel)

        if CommandLine.arguments.contains("--smoke-activity") {
            timerPanel.close()
            smokeActivityPersistence()
            await smokeActivityHistory()
            print("Native activity smoke test passed.")
            exit(0)
        }

        let originalVolume = model.player.volume
        model.player.volume = 0
        for station in RadioStation.allCases {
            model.player.select(station)
            model.player.play()
            var started = false
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(500))
                if let error = model.player.error {
                    model.player.volume = originalVolume
                    smokeFailure("\(station.title): \(error)")
                    return
                }
                if model.player.isPlaying { started = true; break }
            }
            guard started else {
                model.player.volume = originalVolume
                smokeFailure("\(station.title) did not start within 30 seconds")
                return
            }
            let actualState = try? await model.player.webView.evaluateJavaScript("player.getPlayerState()")
            guard actualState as? Int == 1 else { smokeFailure("YouTube did not confirm playing state"); return }
            let actualVideo = try? await model.player.webView.evaluateJavaScript("player.getVideoData().video_id")
            guard actualVideo as? String == station.videoID else {
                smokeFailure("\(station.title) selected the wrong stream"); return
            }
            print("PASS: \(station.title) plays through the official YouTube API")
            await smokeVideoChrome(model.player)
            if station == .defaultStation {
                model.player.volume = 0.01
                let marker = UUID().uuidString
                _ = try? await model.player.webView.evaluateJavaScript("window.navigationMarker = '\(marker)'")
                await smokeNavigation(model)
                let playing = try? await model.player.webView.evaluateJavaScript("player.getPlayerState()")
                let preserved = try? await model.player.webView.evaluateJavaScript("window.navigationMarker")
                guard playing as? Int == 1, preserved as? String == marker else {
                    smokeFailure("Opening Activity interrupted or reloaded the music"); return
                }
                model.player.volume = 0
                print("PASS: Activity navigation works during playback without restarting the stream")
            }
        }

        timerPanel.orderOut(nil)
        await smokeVideoQuality(model)
        timerPanel.close()
        try? await Task.sleep(for: .milliseconds(300))
        let marker = UUID().uuidString
        _ = try? await model.player.webView.evaluateJavaScript("window.handoffMarker = '\(marker)'")
        let panel = menuBarPanel(model)
        panel.orderFront(nil)
        try? await Task.sleep(for: .seconds(1))
        guard !panel.isOpaque,
              panel.contentView?.layer?.cornerRadius == MenuBarView.cornerRadius,
              panel.contentView?.superview?.layer?.cornerRadius == MenuBarView.cornerRadius else {
            smokeFailure("The outer menu-bar window did not use the rounded preview shape"); return
        }
        guard model.player.surfaces.activeSurface?.presentation == .menuBar,
              model.player.webView.window === panel,
              model.player.webView.frame.width >= MenuBarView.size.width,
              model.player.webView.frame.height >= MenuBarView.size.height else {
            smokeFailure("The menu-bar panel did not take the full-background live video"); return
        }
        let menuState = try? await model.player.webView.evaluateJavaScript("player.getPlayerState()")
        let preservedMarker = try? await model.player.webView.evaluateJavaScript("window.handoffMarker")
        guard menuState as? Int == 1, preservedMarker as? String == marker else {
            smokeFailure("Opening the menu-bar panel reloaded or stopped the video"); return
        }
        let frame = model.player.webView.frame
        let pointerEvents = try? await model.player.webView.evaluateJavaScript("getComputedStyle(document.getElementById('player')).pointerEvents")
        let controls = try? await model.player.webView.evaluateJavaScript("new URL(player.getIframe().src).searchParams.get('controls')")
        guard frame.minY < 0,
              frame.maxY > MenuBarView.size.height,
              abs(frame.width / frame.height - 16 / 9) < 0.001,
               pointerEvents as? String == "none", controls as? String == "1" else {
            smokeFailure("YouTube chrome or hover controls can enter the menu background"); return
        }
        print("PASS: YouTube player stays 16:9, edges are cropped, and background hover is disabled")
        await smokeVideoChrome(model.player)
        if let path = ProcessInfo.processInfo.environment["LOFI_BACKGROUND_CAPTURE"],
           let surface = model.player.surfaces.activeSurface {
            do {
                let configuration = WKSnapshotConfiguration()
                configuration.rect = model.player.webView.convert(surface.bounds, from: surface)
                let image = try await model.player.webView.takeSnapshot(configuration: configuration)
                guard let tiff = image.tiffRepresentation,
                      let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    smokeFailure("Could not capture the live background"); return
                }
                try data.write(to: URL(fileURLWithPath: path))
            } catch {
                smokeFailure("Live background capture failed: \(error)"); return
            }
        }
        await smokeMenuBarRoom(model, panel: panel)
        let afterRoom = try? await model.player.webView.evaluateJavaScript("window.handoffMarker")
        let afterRoomState = try? await model.player.webView.evaluateJavaScript("player.getPlayerState()")
        guard afterRoom as? String == marker, afterRoomState as? Int == 1 else {
            smokeFailure("Switching between music and room reloaded or interrupted playback"); return
        }
        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(500))
        guard !model.player.surfaces.isVideoVisible, model.player.webView.frame.size == CGSize(width: 320, height: 180) else {
            smokeFailure("Closing the menu-bar panel did not return the video to its background host"); return
        }
        panel.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(500))
        guard model.player.webView.window === panel else {
            smokeFailure("Reopening the menu-bar panel did not recover the video"); return
        }
        panel.close()
        try? await Task.sleep(for: .milliseconds(500))
        guard !model.player.surfaces.isVideoVisible, model.player.webView.superview != nil else {
            smokeFailure("Closing a video host left the live player orphaned"); return
        }
        print("PASS: menu-bar music/room switching and closing/reopening preserve the same live stream")

        model.player.pause()
        try? await Task.sleep(for: .seconds(6))
        let paused = try? await model.player.webView.evaluateJavaScript("player.getPlayerState()")
        guard paused as? Int == 2 else { smokeFailure("YouTube did not pause"); return }
        print("PASS: native pause reaches YouTube and stays paused through a playback-monitor interval")

        // WebKit intentionally suspends inaudible autoplay in hidden windows.
        // Use 1% volume to exercise real background-audio behavior.
        model.player.volume = 0.01
        model.player.play()
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(500))
            if model.player.isPlaying { break }
        }
        guard model.player.isPlaying else { smokeFailure("Player did not resume before closing the window"); return }
        model.selectMode(.focus)
        model.setDuration(600)
        model.toggleTimer()
        NSApp.windows.first { $0.title == "Lofitime" }?.close()
        let backgroundSeconds = max(3, Int(ProcessInfo.processInfo.environment["LOFI_BACKGROUND_SECONDS"] ?? "") ?? 3)
        let initialPosition = try? await model.player.webView.evaluateJavaScript("player.getCurrentTime()") as? Double
        let backgroundMarker = UUID().uuidString
        _ = try? await model.player.webView.evaluateJavaScript("window.backgroundMarker = '\(backgroundMarker)'")
        try? await Task.sleep(for: .seconds(backgroundSeconds))
        guard !model.player.surfaces.isVideoVisible,
              model.player.webView.frame.size == CGSize(width: 320, height: 180) else {
            smokeFailure("The background player retained a full-size video surface"); return
        }
        let background = try? await model.player.webView.evaluateJavaScript("player.getPlayerState()")
        let finalPosition = try? await model.player.webView.evaluateJavaScript("player.getCurrentTime()") as? Double
        let retainedMarker = try? await model.player.webView.evaluateJavaScript("window.backgroundMarker")
        guard background as? Int == 1, let initialPosition, let finalPosition,
              finalPosition - initialPosition >= Double(backgroundSeconds) * 0.8,
              retainedMarker as? String == backgroundMarker else {
            smokeFailure("Music stopped after closing the studio (state: \(String(describing: background)))")
            return
        }
        print("PASS: music advances for \(backgroundSeconds) seconds with every window closed, without reloading")

        // Simulate the unexpected pause that WebKit/YouTube can emit in the background.
        _ = try? await model.player.webView.evaluateJavaScript("radioPause()")
        try? await Task.sleep(for: .seconds(1))
        guard model.player.isPlaying || model.player.isLoading else {
            smokeFailure("An unexpected pause discarded the listening intent"); return
        }
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            if model.player.isPlaying { break }
        }
        let recovered = try? await model.player.webView.evaluateJavaScript("player.getPlayerState()")
        guard recovered as? Int == 1, model.timer.status == .running else {
            smokeFailure("The radio did not recover an unexpected background pause (player: \(String(describing: recovered)), timer: \(model.timer.status), loading: \(model.player.isLoading), error: \(model.player.error ?? "none"))"); return
        }
        print("PASS: an unexpected background pause recovers while the focus timer keeps running")
        model.player.pause()
        try? await Task.sleep(for: .milliseconds(500))
        model.player.play()
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(500))
            if model.player.isPlaying { break }
        }
        guard model.player.isPlaying else { smokeFailure("Could not resume music from the menu bar with the window closed"); return }
        print("PASS: music can pause and resume with the studio window closed")

        model.player.select(.lofi)
        for _ in 0..<60 {
            try? await Task.sleep(for: .milliseconds(500))
            if model.player.isPlaying { break }
            if model.player.error != nil { break }
        }
        guard model.player.isPlaying else {
            smokeFailure("Could not change stations with the app window closed (ready: \(model.player.isReady), loading: \(model.player.isLoading), error: \(model.player.error ?? "none"))"); return
        }
        print("PASS: a new station loads with the studio window closed")

        AppDelegate.openStudio?()
        try? await Task.sleep(for: .seconds(1))
        guard NSApp.windows.contains(where: { $0.title == "Lofitime" && $0.isVisible }) else {
            smokeFailure("The studio did not reopen")
            return
        }
        print("PASS: the studio reopens after closing")
        model.player.pause()
        model.player.volume = originalVolume
        print("Native smoke test passed.")
        exit(0)
    }

    @MainActor private static func smokeVideoChrome(_ player: RadioPlayer) async {
        do {
            guard let frame = player.diagnosticFrame else {
                smokeFailure("The YouTube embed frame was unavailable for the chrome check"); return
            }
            let cleanVideo = try await player.webView.callAsyncJavaScript("""
                const video = document.querySelector('video');
                const overlays = document.querySelectorAll('.ytp-chrome-top, .ytp-chrome-bottom, .ytp-title, .ytp-title-link, .ytp-impression-link, .ytp-watermark, .ytp-bezel, .player-control-play-pause-icon, .ytPlayerProgressBarHost');
                return Boolean(video && video.getClientRects().length && video.readyState >= 2) &&
                    getComputedStyle(video).objectFit === 'contain' &&
                    [...overlays].every(node => getComputedStyle(node).display === 'none');
                """, arguments: [:], in: frame, contentWorld: .page)
            guard cleanVideo as? Bool == true else {
                smokeFailure("YouTube playback UI is still visible over \(player.station.title)"); return
            }
            print("PASS: \(player.station.title) video is visible without YouTube titles or playback overlays")
        } catch {
            smokeFailure("Could not verify the YouTube background: \(error)")
        }
    }

    @MainActor private static func smokeVideoQuality(_ model: AppModel) async {
        guard let studio = NSApp.windows.first(where: { $0.title == "Lofitime" }) else {
            smokeFailure("Studio unavailable for quality settings"); return
        }
        let marker = UUID().uuidString
        _ = try? await model.player.webView.evaluateJavaScript("window.qualityMarker = '\(marker)'")
        guard await click("navigation-Settings", in: studio),
              await click("video-quality-settings", in: studio) else {
            smokeFailure("Video quality settings could not be opened"); return
        }
        try? await Task.sleep(for: .seconds(1))
        guard model.player.surfaces.activeSurface?.presentation == .quality,
              model.player.surfaces.isInteractive, let frame = model.player.diagnosticFrame else {
            smokeFailure("Quality settings did not host the same interactive YouTube player (surface: \(String(describing: model.player.surfaces.activeSurface?.presentation)), interactive: \(model.player.surfaces.isInteractive), sheet: \(studio.attachedSheet != nil))"); return
        }
        do {
            let opened = try await model.player.webView.callAsyncJavaScript("""
                const gear = document.querySelector('.ytp-settings-button, .player-settings-icon');
                if (!gear || getComputedStyle(gear).display === 'none') return 'Quality gear is hidden';
                gear.click();
                await new Promise(resolve => setTimeout(resolve, 400));
                const quality = [...document.querySelectorAll('.ytp-menuitem, [role="menuitem"]')].find(item =>
                    item.textContent.includes('Quality'));
                if (!quality) return 'Quality row is missing';
                quality.click();
                await new Promise(resolve => setTimeout(resolve, 400));
                return true;
                """, arguments: [:], in: frame, contentWorld: .page)
            guard opened as? Bool == true else {
                smokeFailure("YouTube's real quality menu is unavailable: \(String(describing: opened))"); return
            }
            try? await Task.sleep(for: .milliseconds(300))
            let options = try await model.player.webView.callAsyncJavaScript("""
                return [...document.querySelectorAll('.ytp-quality-menu .ytp-menuitem, [role="menuitem"], [role="menuitemradio"]')]
                    .map(item => item.textContent.trim());
                """, arguments: [:], in: frame, contentWorld: .page)
            guard let options = options as? [String], options.contains(where: { $0.hasPrefix("720p") || $0.hasPrefix("1080p") }) else {
                smokeFailure("YouTube quality menu did not list HD choices (\(String(describing: options)))"); return
            }
            let selected = try await model.player.webView.callAsyncJavaScript("""
                const choice = [...document.querySelectorAll('.ytp-quality-menu .ytp-menuitem, [role="menuitem"], [role="menuitemradio"]')]
                    .find(item => item.textContent.trim().startsWith('720p'));
                if (!choice) return false;
                choice.click();
                return true;
                """, arguments: [:], in: frame, contentWorld: .page)
            guard selected as? Bool == true else {
                smokeFailure("YouTube's 720p quality option could not be selected"); return
            }
            // Close the native sheet without changing the user's playback intent.
            guard let sheet = studio.attachedSheet, await click("video-quality-done", in: sheet) else {
                smokeFailure("Video quality settings could not be dismissed"); return
            }
            guard await click("navigation-Activity", in: studio) else {
                smokeFailure("Activity could not reopen after quality settings"); return
            }
            try? await Task.sleep(for: .milliseconds(500))
            let preserved = try await model.player.webView.evaluateJavaScript("window.qualityMarker")
            guard preserved as? String == marker else {
                smokeFailure("Quality settings reloaded the radio"); return
            }
            let closed = try await model.player.webView.callAsyncJavaScript("""
                return ![...document.querySelectorAll('[role="menuitem"], [role="menuitemradio"]')].some(node =>
                    node.getClientRects().length && getComputedStyle(node).visibility !== 'hidden');
                """, arguments: [:], in: frame, contentWorld: .page)
            guard closed as? Bool == true else {
                smokeFailure("YouTube's quality picker remained over the background after closing Settings"); return
            }
            print("PASS: Settings opens YouTube's actual HD choices and selects 720p without reloading playback")
        } catch {
            smokeFailure("Could not verify quality settings: \(error)")
        }
    }

    @MainActor private static func smokeNavigation(_ model: AppModel) async {
        guard let window = NSApp.windows.first(where: { $0.title == "Lofitime" }) else {
            smokeFailure("The studio is missing for the navigation check"); return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(300))
        guard await click("navigation-Activity", in: window), model.section == .sessions else {
            smokeFailure("Clicking Activity in the studio sidebar did not open it"); return
        }
        guard accessibilityElement("activity-room", in: window) != nil,
              accessibilityElement("activity-session-heading", in: window) == nil,
              accessibilityElement("navigation-Studio", in: window) == nil,
              accessibilityElement("desk-statistics", in: window) == nil else {
            smokeFailure("Activity did not open the study room"); return
        }
        guard let room = room(in: window.contentView), room.bounds.height > 180 else {
            smokeFailure("The room has insufficient space in the activity page"); return
        }
        guard await click("activity-view-stats", in: window) else { return }
        try? await Task.sleep(for: .milliseconds(800))
        guard room.showsStats, !room.isTransitioning,
              await click("activity-day-\(model.activity.endDate.timeIntervalSince1970)", in: window),
              accessibilityElement("activity-session-heading", in: window) != nil,
              let record = model.records.first,
              accessibilityElement("session-record-\(record.id)", in: window) != nil else {
            smokeFailure("Clicking today's weekly bar did not reveal its sessions"); return
        }
        guard await click("activity-close-details", in: window),
              accessibilityElement("activity-session-heading", in: window) == nil else {
            smokeFailure("Closing daily sessions did not return to Activity"); return
        }
        guard await click("navigation-Settings", in: window), model.section == .settings else {
            smokeFailure("The studio sidebar could not open Settings"); return
        }
        for appearance in AppAppearance.allCases {
            guard await click("theme-\(appearance.rawValue)", in: window), model.preferences.appearance == appearance else {
                smokeFailure("Theme selection did not apply \(appearance.title)"); return
            }
        }
        guard await click("navigation-Activity", in: window), model.section == .sessions else {
            smokeFailure("The sidebar could not switch between Settings and Activity"); return
        }
        print("PASS: Activity/Settings navigation, desk-screen stats, daily sessions, and all five themes work with real clicks")
    }

    @MainActor private static func accessibilityElement(_ identifier: String, in root: AnyObject) -> AnyObject? {
        if root.accessibilityIdentifier?() == identifier { return root }
        if let sheet = (root as? NSWindow)?.attachedSheet,
           let match = accessibilityElement(identifier, in: sheet) { return match }
        for child in root.accessibilityChildren?() ?? [] {
            if let match = accessibilityElement(identifier, in: child as AnyObject) { return match }
        }
        return nil
    }

    @MainActor private static func click(_ identifier: String, in window: NSWindow) async -> Bool {
        let window = window.attachedSheet ?? window
        guard let element = accessibilityElement(identifier, in: window) else {
            smokeFailure("Missing native UI element: \(identifier)"); return false
        }
        guard let frame = element.accessibilityFrame?(), !frame.isEmpty else { return false }
        let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        // Mouse events exercise hit testing; accessibilityPerformPress would bypass an
        // invisible background view intercepting clicks on the sidebar or activity grid.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) else { return false }
            NSApp.postEvent(event, atStart: false)
        }
        try? await Task.sleep(for: .milliseconds(300))
        return true
    }

    @MainActor private static func textFields(in view: NSView?) -> [NSTextField] {
        guard let view else { return [] }
        return (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    @MainActor private static func room(in view: NSView?) -> StudyRoomScene.RoomView? {
        guard let view else { return nil }
        if let room = view as? StudyRoomScene.RoomView { return room }
        return view.subviews.compactMap { room(in: $0) }.first
    }

    @MainActor private static func menuBarPanel(_ model: AppModel) -> NSPanel {
        model.menuBarShowsRoom = false
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: MenuBarView.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: MenuBarView(model: model))
        panel.level = .floating
        panel.center()
        return panel
    }

    @MainActor private static func smokeMenuBarRoom(_ model: AppModel, panel: NSPanel) async {
        let status = model.timer.status
        let duration = model.timer.duration
        let loaded = model.player.hasLoaded
        let playing = model.player.isPlaying
        let volume = model.player.volume
        if playing { model.player.volume = 0.01 }
        defer { model.player.volume = volume }
        guard await click("menu-bar-room-toggle", in: panel), model.menuBarShowsRoom,
              let room = room(in: panel.contentView),
              room.bounds.width > 250, room.bounds.height > 150,
              accessibilityElement("room-timer-toggle", in: panel) != nil,
              model.timer.status == status, model.timer.duration == duration, model.player.hasLoaded == loaded else {
            smokeFailure("Menu-bar room switch lost the timer or failed to display the room"); return
        }
        if playing {
            let before = try? await model.player.webView.evaluateJavaScript("player.getCurrentTime()") as? Double
            try? await Task.sleep(for: .seconds(6))
            let after = try? await model.player.webView.evaluateJavaScript("player.getCurrentTime()") as? Double
            guard let before, let after, after - before >= 4.5, model.player.isPlaying,
                  !model.player.surfaces.isVideoVisible,
                  model.player.webView.frame.size == CGSize(width: 320, height: 180) else {
                smokeFailure("Music stopped or kept a full-size video surface while the popup showed the room"); return
            }
            print("PASS: music advances while the menu-bar popup shows the room and the video surface stays small")
        }
        guard await click("menu-bar-room-toggle", in: panel), !model.menuBarShowsRoom,
              accessibilityElement("room-timer-toggle", in: panel) == nil,
              model.timer.status == status, model.timer.duration == duration,
              !room.isPlaying else {
            smokeFailure("Menu-bar music switch lost timer state or kept rendering the hidden room"); return
        }
        print("PASS: one button switches the menu-bar popup between music/timer and the cozy room")
    }

    @MainActor private static func smokeRoomGestures(_ room: StudyRoomScene.RoomView, in window: NSWindow) async {
        guard accessibilityElement("activity-zoom-in", in: window) == nil,
              let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 40, wheel2: 0, wheel3: 0),
              let event = NSEvent(cgEvent: scroll) else {
            smokeFailure("Old zoom button remains or native scroll event is unavailable"); return
        }
        let originalScale = room.pointOfView?.camera?.orthographicScale ?? 0
        room.scrollWheel(with: event)
        guard room.cameraState.zoom > 1, (room.pointOfView?.camera?.orthographicScale ?? 0) < originalScale else {
            smokeFailure("Scrolling did not zoom the room"); return
        }
        let origin = NSPoint(x: room.bounds.midX, y: room.bounds.midY)
        func mouse(_ type: NSEvent.EventType, at point: NSPoint, count: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: room.convert(point, to: nil), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        }
        room.mouseDown(with: mouse(.leftMouseDown, at: origin))
        room.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: origin.x + 34, y: origin.y + 19)))
        room.mouseUp(with: mouse(.leftMouseUp, at: origin))
        guard room.cameraState.pan.width != 0, room.cameraState.pan.height != 0 else {
            smokeFailure("Dragging did not move around the room"); return
        }
        room.mouseDown(with: mouse(.leftMouseDown, at: origin, count: 2))
        guard room.cameraState == RoomCameraState() else {
            smokeFailure("Double-click did not reset the room"); return
        }
        // Leave a distinctive view to check restoration after browsing the desktop.
        room.scrollWheel(with: event)
        room.mouseDown(with: mouse(.leftMouseDown, at: origin))
        room.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: origin.x - 15, y: origin.y + 5)))
        room.mouseUp(with: mouse(.leftMouseUp, at: origin))
        try? await Task.sleep(for: .milliseconds(200))
    }

    @MainActor private static func smokeRoomModels() {
        for minutes in [0, 25, 120, 360, 720] {
            let now = Date()
            let records = [SessionRecord(finishedAt: now, duration: Double(minutes) * 60, intention: "Room diagnostic")]
            let growth = FocusRoom(records: records, through: now)
            let scene = StudyRoomBuilder.scene(growth: growth, theme: .candlelight)
            for name in ["desk", "computer", "window", "bed", "chair"] {
                guard let model = scene.rootNode.childNode(withName: name, recursively: true),
                      !model.childNodes.isEmpty, model.boundingBox.max.y > model.boundingBox.min.y else {
                    smokeFailure("Room essential is missing at \(minutes) minutes: \(name)"); return
                }
            }
            var books = 0
            var count = 0
            scene.rootNode.enumerateChildNodes { node, _ in
                if node.name?.hasPrefix("book-") == true { books += 1 }
                count += 1
            }
            guard books == growth.bookCount, count < 1_500 else {
                smokeFailure("The room's books or geometry budget did not match its growth"); return
            }
            if minutes == 0 {
                guard scene.rootNode.childNode(withName: "desk-plant", recursively: true) == nil,
                      scene.rootNode.childNode(withName: "bookshelf", recursively: true) == nil else {
                    smokeFailure("An empty room already has grown decor"); return
                }
            } else if minutes == 720 {
                for name in ["rug", "desk-lamp", "floor-lamp", "bookshelf", "hanging-plants", "blossom", "fairy-lights", "sleeping-cat",
                             "pinboard", "open-notebook", "knitted-pouf", "bedside-candle", "keepsake-shelf", "desktop-screen"] {
                    guard scene.rootNode.childNode(withName: name, recursively: true) != nil else {
                        smokeFailure("A fully grown room is missing \(name)"); return
                    }
                }
            }
            let view = StudyRoomScene.RoomView(frame: NSRect(x: 0, y: 0, width: 520, height: 285))
            view.scene = scene
            view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
            view.fitCamera()
            let scale = view.pointOfView?.camera?.orthographicScale ?? 0
            view.cameraState.zoom = 1.5
            view.fitCamera()
            guard scale > 0, abs((view.pointOfView?.camera?.orthographicScale ?? 0) * 1.5 - scale) < 0.01 else {
                smokeFailure("The room camera did not frame and zoom correctly"); return
            }
            view.hasAnimation = true
            view.updateAnimation()
            guard !view.isPlaying, scene.isPaused else { smokeFailure("An offscreen room kept rendering"); return }
            view.scene = nil
        }
        print("PASS: all five room stages contain real 3D furniture, bounded books/plants, lights, and an idle offscreen renderer")
    }

    private static func smokeFailure(_ message: String) {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    private struct DiagnosticArchive: Encodable {
        let timer: FocusTimer
        let records: [SessionRecord]
        let intention: String
    }

    @MainActor private static func smokeActivityHistory() async {
        let suite = "com.lofimen.diagnostics.history"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let monthStart = Calendar.current.dateInterval(of: .month, for: now)!.start
        let oldDate = Calendar.current.date(byAdding: .month, value: -1, to: monthStart)!.addingTimeInterval(3_600)
        let old = SessionRecord(finishedAt: oldDate, duration: 1_800, intention: "Older focus")
        let recent = SessionRecord(finishedAt: now, duration: 43_200, intention: "A cozy study")
        defaults.set(try? JSONEncoder().encode(DiagnosticArchive(timer: FocusTimer(), records: [recent, old], intention: "")), forKey: "session.v1")
        let model = AppModel(defaults: defaults)
        model.section = .sessions
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 740), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StudioView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try? await Task.sleep(for: .milliseconds(500))
        guard let room = room(in: window.contentView) else { smokeFailure("Missing interactive room"); return }
        await smokeRoomGestures(room, in: window)
        let scene = room.scene
        let camera = room.cameraState
        guard await click("activity-view-stats", in: window) else { return }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            guard room.isTransitioning, let node = room.pointOfView,
                  abs(node.presentation.position.x - node.position.x) > 0.01 else {
                smokeFailure("View stats jumped to the desktop instead of animating the camera (transitioning: \(room.isTransitioning), playing: \(room.isPlaying), paused: \(String(describing: room.scene?.isPaused)), target: \(String(describing: room.pointOfView?.position)), presentation: \(String(describing: room.pointOfView?.presentation.position)))"); return
            }
        }
        try? await Task.sleep(for: .milliseconds(800))
        guard room.desktopHost?.isHidden == false, room.desktopHost?.frame == room.bounds,
              await click("activity-week-previous", in: window),
              await click("activity-week-current", in: window),
              await click("desk-stats-month", in: window),
              await click("activity-month-previous", in: window),
              room.scene === scene,
              await click("activity-month-day-\(Calendar.current.startOfDay(for: oldDate).timeIntervalSince1970)", in: window),
              accessibilityElement("session-record-\(old.id)", in: window) != nil,
              await click("activity-close-details", in: window),
              await click("activity-month-current", in: window),
              accessibilityElement("activity-session-heading", in: window) == nil,
              await click("activity-view-stats", in: window) else {
            smokeFailure("Weekly/monthly browsing changed room growth or lost historical sessions"); return
        }
        try? await Task.sleep(for: .milliseconds(800))
        guard room.cameraState == camera, room.desktopHost?.isHidden == true else {
            smokeFailure("Leaving the desktop did not restore the explored room view"); return
        }
        // The normal stats layout must stay readable and fill the pane at the smallest size.
        window.setContentSize(CGSize(width: 660, height: 500))
        guard await click("activity-view-stats", in: window) else { return }
        try? await Task.sleep(for: .milliseconds(800))
        guard let total = accessibilityElement("activity-month-total", in: window)?.accessibilityFrame?(), total.height >= 30,
              let footer = accessibilityElement("activity-all-time", in: window)?.accessibilityFrame?(),
              room.bounds.contains(room.convert(window.convertFromScreen(footer), from: nil)),
              room.desktopHost?.frame == room.bounds else {
            smokeFailure("Stats remained scaled to the monitor or clipped in the compact window"); return
        }
        guard await click("activity-view-stats", in: window) else { return }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !room.isTransitioning {
            smokeFailure("Back to room did not animate the camera out"); return
        }
        // Reverse an in-flight return; stale completions must not hide the reopened page.
        guard await click("activity-view-stats", in: window) else { return }
        try? await Task.sleep(for: .milliseconds(800))
        guard room.showsStats, !room.isTransitioning, room.desktopHost?.isHidden == false,
              await click("activity-view-stats", in: window) else {
            smokeFailure("Quickly reversing the stats transition left a stale page"); return
        }
        try? await Task.sleep(for: .milliseconds(800))
        guard room.cameraState == camera, room.desktopHost?.isHidden == true else {
            smokeFailure("Reversing the transition lost the explored room view"); return
        }
        window.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(200))
        room.updateAnimation()
        // SwiftUI may have dismantled the native view after it scrolled offscreen.
        guard !room.isPlaying, room.scene?.isPaused != false else {
            smokeFailure("A hidden study room continued to render (playing: \(room.isPlaying), scene paused: \(String(describing: room.scene?.isPaused)))"); return
        }
        print("PASS: animated desk zoom, full-resolution stats at minimum size, quick transition reversal, history, and restored room view")
    }

    @MainActor private static func smokeActivityPersistence() {
        let suite = "com.lofimen.diagnostics.activity"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        var timer = FocusTimer()
        timer.setDuration(1)
        timer.start(at: yesterday)
        let archive = DiagnosticArchive(timer: timer, records: [], intention: "Saved focus")
        defaults.set(try? JSONEncoder().encode(archive), forKey: "session.v1")
        var preferences = Preferences()
        preferences.completionSound = false
        preferences.startMusicWithFocus = false
        defaults.set(try? JSONEncoder().encode(preferences), forKey: "preferences.v1")
        let restored = AppModel(defaults: defaults)
        restored.tick()
        guard restored.records.count == 1, restored.activity.allTimeDuration == 1,
              restored.todayRecords.isEmpty, restored.records.first?.finishedAt == yesterday.addingTimeInterval(1) else {
            smokeFailure("An overdue restored session was lost, duplicated, or assigned to today"); return
        }
        let relaunched = AppModel(defaults: defaults)
        guard relaunched.records == restored.records else {
            smokeFailure("Completed activity changed after relaunch"); return
        }
        print("PASS: an overdue saved session is recorded on its completion day exactly once across relaunches")
        relaunched.menuBarShowsRoom = true
        guard AppModel(defaults: defaults).menuBarShowsRoom else {
            smokeFailure("The menu-bar room preference did not survive relaunch"); return
        }

        let actions: [(String, () -> Void)] = [
            ("pause", { relaunched.toggleTimer() }),
            ("reset", { relaunched.resetTimer() }),
            ("mode change", { relaunched.selectMode(.shortBreak) }),
            ("skip", { relaunched.skipSession() }),
            ("duration edit", { relaunched.setDuration(90) })
        ]
        for (name, action) in actions {
            relaunched.selectMode(.focus)
            relaunched.setDuration(1)
            let count = relaunched.records.count
            relaunched.toggleTimer()
            // Simulate a busy UI thread: the timer callback cannot run before the user's action.
            Thread.sleep(forTimeInterval: 1.05)
            action()
            guard relaunched.records.count == count + 1, relaunched.records.first?.duration == 1 else {
                smokeFailure("An overdue focus session was discarded by \(name)"); return
            }
            if name == "pause", relaunched.timer.status != .ready {
                smokeFailure("Pausing at completion started the next mode"); return
            }
        }
        print("PASS: pause, reset, skip, mode changes, and duration edits preserve a just-completed session")
    }

    @MainActor private static func renderActivityExample(to url: URL, appearance: AppAppearance,
                                                        size: CGSize = CGSize(width: 820, height: 620), showStats: Bool = false) async throws {
        let now = Date()
        let calendar = Calendar.current
        let records = (0..<45).compactMap { offset -> SessionRecord? in
            let duration = [10_800, 7_200, 10_800, 5_400, 9_000, 7_200, 3_600, 0, 7_200, 0, 2_400, 10_800, 4_800, 600, 1_800][offset % 15]
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            return duration > 0 ? SessionRecord(finishedAt: date, duration: Double(duration), intention: "Example session") : nil
        }
        let suite = "com.lofimen.diagnostics.preview"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(DiagnosticArchive(timer: FocusTimer(), records: records, intention: "")), forKey: "session.v1")
        let model = AppModel(defaults: defaults)
        model.section = .sessions
        model.preferences.appearance = appearance
        try await render(StudioView(model: model).frame(width: size.width, height: size.height), to: url, prepare: { window in
            if showStats { _ = await click("activity-view-stats", in: window) }
        })
        if appearance == .candlelight && !showStats {
            model.menuBarShowsRoom = true
            try await render(MenuBarView(model: model), to: url.deletingLastPathComponent().appendingPathComponent("menu-bar-room.png"))
        }
    }
    #endif
}
