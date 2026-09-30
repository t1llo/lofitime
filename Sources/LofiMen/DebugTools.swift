import AppKit
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
        // Diagnostics need a studio even in that case, before its .task can run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard !hasRun else { return }
            if let window = NSApp.windows.first(where: { $0.title == "Lofitime" }) {
                window.makeKeyAndOrderFront(nil)
            } else if let menu = NSApp.mainMenu?.items.compactMap(\.submenu).first(where: {
                $0.items.contains(where: { $0.title == "Open My Studio" })
            }), let index = menu.items.firstIndex(where: { $0.title == "Open My Studio" }) {
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
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
           CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for section in StudioSection.allCases {
                        model.section = section
                        try await render(StudioView(model: model).frame(width: 700, height: 540),
                                   to: directory.appendingPathComponent("\(section == .studio ? "studio" : section == .sessions ? "sessions" : "preferences").png"))
                    }
                    try await render(MenuBarView(model: model), to: directory.appendingPathComponent("menu-bar.png"))
                    model.section = .studio
                    try await render(VideoFocusScene(model: model, presentation: .menuBar, showingSettings: true)
                        .frame(width: MenuBarView.size.width, height: MenuBarView.size.height)
                        .environment(\.roomTheme, model.preferences.appearance.palette).preferredColorScheme(.dark),
                                     to: directory.appendingPathComponent("menu-bar-settings.png"))
                    for station in [RadioStation.sleepy, .house] {
                        model.player.select(station)
                        try await render(MenuBarView(model: model), to: directory.appendingPathComponent("menu-bar-\(station.rawValue).png"))
                    }
                    if model.player.station != .defaultStation { model.player.select(.defaultStation) }
                    model.preferences.appearance = .catppuccin
                    try await render(StudioView(model: model).frame(width: 700, height: 540),
                                     to: directory.appendingPathComponent("studio-catppuccin.png"))
                    try await render(MenuBarView(model: model), to: directory.appendingPathComponent("menu-bar-catppuccin.png"))
                    try await renderActivityExample(to: directory.appendingPathComponent("activity-example.png"))
                    print("Native previews saved to \(directory.path)")
                    exit(0)
                } catch {
                    fputs("Preview failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        } else if CommandLine.arguments.contains("--smoke-test") {
            Task { @MainActor in await smoke(model) }
        }
        #endif
    }

    #if DEBUG
    @MainActor private static func render<V: View>(_ view: V, to url: URL) async throws {
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

    @MainActor private static func smoke(_ model: AppModel) async {
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
              model.activity.totalSessions == 1, model.activity.activeDays == 1 else {
            smokeFailure("A completed exact-duration session did not update activity")
            return
        }
        guard model.activity.weeks.flatMap({ $0 }).first(where: { $0.date == model.activity.endDate })?.flowers == 1 else {
            smokeFailure("A short focus session did not grow the first flower"); return
        }
        for name in ["flower_purpleA", "flower_purpleB", "flower_redA", "flower_yellowA", "grass", "plant_bushDetailed", "tree_oak", "tree_pineRoundA", "mushroom_red", "rock_smallA"] {
            let modelNode = GardenBuilder.model(name, height: 1)
            guard !modelNode.childNodes.isEmpty, modelNode.boundingBox.max.y > modelNode.boundingBox.min.y else {
                smokeFailure("Bundled garden model did not load: \(name)"); return
            }
        }
        print("PASS: a completed focus session grows a flower; bundled CC0 garden meshes load correctly")
        let forest = FocusActivity(records: [SessionRecord(finishedAt: model.activity.endDate, duration: 18_000, intention: "Forest diagnostic")], through: Date())
        let forestScene = GardenBuilder.scene(weeks: forest.gardenWeeks)
        guard forestScene.rootNode.childNodes.filter({ $0.name?.hasPrefix("day-") == true || $0.name == "future-day" }).count == 35,
              let tree = forestScene.rootNode.childNode(withName: "forest-tree", recursively: true),
              let fox = forestScene.rootNode.childNode(withName: "forest-fox", recursively: true),
              let bee = forestScene.rootNode.childNode(withName: "forest-bee", recursively: true),
              tree.boundingBox.max.y * tree.scale.y > 1.4,
              let sound = ForestAmbience.makeSound(), abs(sound.duration - 12) < 0.1 else {
            smokeFailure("Daily forest tiles, tall trees, wildlife, or synthesized audio did not load"); return
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            guard fox.hasActions, bee.hasActions else {
                smokeFailure("Forest wildlife was not animated"); return
            }
        }
        let map = GardenSceneView.GardenView(frame: NSRect(x: 0, y: 0, width: 436, height: 260))
        map.scene = forestScene
        map.pointOfView = forestScene.rootNode.childNode(withName: "camera", recursively: false)
        map.weekCount = forest.weeks.count
        map.fitCamera()
        let fitted = map.pointOfView?.camera?.orthographicScale ?? 0
        map.zoom = 3
        map.fitCamera()
        guard fitted > 0, abs((map.pointOfView?.camera?.orthographicScale ?? 0) * 3 - fitted) < 0.01 else {
            smokeFailure("Forest camera did not fit or zoom correctly"); return
        }
        map.scene = nil
        print("PASS: five full weeks fit the panel; tall trees, animated foxes/bees, 3× zoom, and 12-second forest audio load")

        model.selectMode(.focus)
        model.banner = nil
        await smokeNavigation(model)
        try? await Task.sleep(for: .milliseconds(300))
        if let window = NSApp.windows.first(where: { $0.title == "Lofitime" }),
           let field = textFields(in: window.contentView).first(where: { $0.stringValue == "25:00" }) {
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
            smokeFailure("The editable countdown is missing from the studio"); return
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

        await smokeVideoQuality(model)

        guard let studioSurface = model.player.surfaces.activeSurface,
              studioSurface.presentation == .studio, studioSurface.window?.isVisible == true else {
            smokeFailure("The live player is not attached to the studio background (surface: \(String(describing: model.player.surfaces.activeSurface?.presentation)), window: \(String(describing: model.player.webView.window?.title)), visible: \(String(describing: model.player.webView.window?.isVisible)))"); return
        }
        let marker = UUID().uuidString
        _ = try? await model.player.webView.evaluateJavaScript("window.handoffMarker = '\(marker)'")
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: MenuBarView.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: MenuBarView(model: model))
        panel.level = .floating
        panel.center()
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
        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(500))
        guard model.player.surfaces.activeSurface === studioSurface,
              model.player.webView.window === studioSurface.window else {
            smokeFailure("Closing the menu-bar panel did not return the video to the studio"); return
        }
        panel.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(500))
        guard model.player.webView.window === panel else {
            smokeFailure("Reopening the menu-bar panel did not recover the video"); return
        }
        panel.close()
        try? await Task.sleep(for: .milliseconds(500))
        guard model.player.webView.window === studioSurface.window else {
            smokeFailure("Closing a video host left the live player orphaned"); return
        }
        print("PASS: the same live video fills the menu-bar panel and returns to the studio without reloading")

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
        guard model.player.isPlaying else { smokeFailure("Could not change stations with the studio window closed"); return }
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
            smokeFailure("Quality settings did not host the same interactive YouTube player"); return
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
            guard await click("navigation-Studio", in: studio) else {
                smokeFailure("Studio could not reopen after quality settings"); return
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
        guard accessibilityElement("activity-session-heading", in: window) != nil,
              let record = model.records.first,
              accessibilityElement("session-record-\(record.id)", in: window) != nil else {
            smokeFailure("Activity did not display the completed focus session"); return
        }
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        if let content = window.contentView,
           let scroll = scrollViews(in: content).first(where: { $0.bounds.width > 300 }),
           let document = scroll.documentView {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(220, max(0, document.bounds.height - scroll.contentView.bounds.height))))
            scroll.reflectScrolledClipView(scroll.contentView)
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard await click("activity-day-\(model.activity.endDate.timeIntervalSince1970)", in: window),
              accessibilityElement("activity-show-all", in: window) != nil else {
            smokeFailure("Clicking today's garden day did not filter the sessions"); return
        }
        guard await click("activity-show-all", in: window),
              accessibilityElement("activity-show-all", in: window) == nil else {
            smokeFailure("Activity's Show all button did not clear the date filter"); return
        }
        guard await click("navigation-Settings", in: window), model.section == .settings,
              await click("navigation-Studio", in: window), model.section == .studio else {
            smokeFailure("The studio sidebar could not switch between Settings and Studio"); return
        }
        print("PASS: real sidebar clicks open Activity, show completed sessions, filter days, and return to Studio")
    }

    @MainActor private static func accessibilityElement(_ identifier: String, in root: AnyObject) -> AnyObject? {
        if root.accessibilityIdentifier?() == identifier { return root }
        for child in root.accessibilityChildren?() ?? [] {
            if let match = accessibilityElement(identifier, in: child as AnyObject) { return match }
        }
        return nil
    }

    @MainActor private static func click(_ identifier: String, in window: NSWindow) async -> Bool {
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

    private static func smokeFailure(_ message: String) {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    @MainActor private static func renderActivityExample(to url: URL) async throws {
        let now = Date()
        let calendar = Calendar.current
        let records = (0..<FocusActivity.historyDays).flatMap { offset -> [SessionRecord] in
            let count = (offset * 7 + offset / 9) % 6
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            return (0..<count).map { _ in SessionRecord(finishedAt: date, duration: 1_500, intention: "Example session") }
        }
        try await render(
            VStack(alignment: .leading, spacing: 20) {
                Text("Focus activity · example data").font(.room(size: 20, weight: .medium))
                FocusGarden(activity: FocusActivity(records: records, through: now), selectedDay: .constant(nil))
            }.padding(28).frame(width: 520)
                .foregroundStyle(RoomTheme.candlelight.text).background(RoomTheme.candlelight.background)
                .environment(\.roomTheme, .candlelight).preferredColorScheme(.dark), to: url)
    }
    #endif
}
