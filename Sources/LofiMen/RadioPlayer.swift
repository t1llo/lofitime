import AppKit
import Observation
import SwiftUI
import WebKit

enum RadioStation: String, CaseIterable, Identifiable {
    case house, lofi, sleepy, synthwave
    static let defaultStation: RadioStation = .house
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lofi: "Study lo-fi"
        case .synthwave: "Synthwave"
        case .sleepy: "Sleepy lo-fi"
        case .house: "Chill house"
        }
    }
    var subtitle: String {
        switch self {
        case .lofi: "lofi hip hop · focus & study"
        case .synthwave: "synthwave · chill & game"
        case .sleepy: "soft beats · sleep & unwind"
        case .house: "lofi house · lounge & chill"
        }
    }
    var videoID: String {
        switch self {
        case .lofi: "rFZHOHl-L8A"
        case .synthwave: "4xDzrJKXOOY"
        case .sleepy: "JD-kMIpDfnY"
        case .house: "3PFJ9SETS4M"
        }
    }
    var symbol: String {
        switch self {
        case .lofi: "cup.and.saucer.fill"
        case .synthwave: "sparkles"
        case .sleepy: "moon.stars.fill"
        case .house: "sun.horizon.fill"
        }
    }
    var focalPoint: CGFloat {
        switch self {
        case .synthwave: 0.38
        case .house: 0.5
        case .lofi, .sleepy: 0.65
        }
    }
}

enum AppResources {
    static let appIcon: NSImage = {
        guard let url = bundle.url(forResource: "app-icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { fatalError("Missing app icon") }
        return image
    }()

    static let menuBarIcon: NSImage = {
        guard let url = bundle.url(forResource: "lofi-head", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { fatalError("Missing menu-bar icon") }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    static var bundle: Bundle {
        let locations = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                         Bundle.main.executableURL?.deletingLastPathComponent()]
        for location in locations.compactMap({ $0 }) {
            if let bundle = Bundle(url: location.appendingPathComponent("LofiMen_LofiMen.bundle")) { return bundle }
        }
        return .main
    }

    private static let artworks: [RadioStation: NSImage] = Dictionary(uniqueKeysWithValues:
        RadioStation.allCases.compactMap { station in
            guard let url = bundle.url(forResource: station.rawValue, withExtension: "jpg"),
                  let image = NSImage(contentsOf: url) else { return nil }
            return (station, image)
        }
    )

    static func artwork(_ station: RadioStation) -> NSImage? { artworks[station] }
}

private final class RadioMessageHandler: NSObject, WKScriptMessageHandler {
    weak var player: RadioPlayer?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        #if DEBUG
        if DebugTools.requested, (message.body as? [String: Bool])?["debugFrame"] == true,
           message.frameInfo.securityOrigin.host == "www.youtube.com",
           message.frameInfo.request.url?.path.hasPrefix("/embed/") == true {
            Task { @MainActor in player?.diagnosticFrame = message.frameInfo }
            return
        }
        #endif
        Task { @MainActor in player?.receive(message.body) }
    }
}

@MainActor @Observable
final class RadioPlayer: NSObject, WKNavigationDelegate {
    private(set) var station: RadioStation
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isReady = false
    private(set) var error: String?
    var volume: Double {
        didSet {
            defaults.set(volume, forKey: "radio.volume")
            evaluate("radioVolume(\(Int(volume * 100)))")
        }
    }

    @ObservationIgnored lazy var webView: WKWebView = makeWebView()
    @ObservationIgnored lazy var surfaces = VideoSurfaceRouter(webView: webView)
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var wantsPlayback = false {
        didSet { if wantsPlayback != oldValue { updatePlaybackActivity() } }
    }
    @ObservationIgnored private var loadTimeout: Task<Void, Never>?
    @ObservationIgnored private var playbackMonitor: Task<Void, Never>?
    @ObservationIgnored private var playbackActivity: NSObjectProtocol?
    @ObservationIgnored private var lastPlaybackPosition: Double?
    @ObservationIgnored private var lastPlaybackProgress = Date()
    @ObservationIgnored private var attemptedResume = false
    @ObservationIgnored private var reconnectAttempts = 0
    @ObservationIgnored private var previousVolume = 0.6
    @ObservationIgnored private var loadID = ""
    #if DEBUG
    @ObservationIgnored var diagnosticFrame: WKFrameInfo?
    #endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        station = RadioStation(rawValue: defaults.string(forKey: "radio.station") ?? "") ?? .defaultStation
        volume = defaults.object(forKey: "radio.volume") as? Double ?? 0.6
        super.init()
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        // Keep overlays hidden in backgrounds; reveal YouTube's real controls only
        // in the interactive player so its supported quality menu remains available.
        configuration.userContentController.addUserScript(WKUserScript(source: """
            if (location.hostname === 'www.youtube.com' && location.pathname.startsWith('/embed/')) {
                const style = document.createElement('style');
                style.textContent = `
                    video { object-fit: contain !important; }
                    html:not([data-lofi-interactive="true"]) :is(
                        .ytp-chrome-top, .ytp-chrome-bottom,
                        .ytp-title, .ytp-title-link, .ytp-title-text,
                        .ytp-impression-link, .ytp-watermark,
                        .ytp-gradient-top, .ytp-gradient-bottom,
                        .ytp-bezel, .ytp-pause-overlay, .ytp-settings-menu,
                        .player-controls-top, .player-controls-bottom, .player-controls-middle,
                        .ytmVideoInfoRendererHost, .ytmProgressBarHost,
                        .ytPlayerProgressBarHost,
                        .ytm-progress-bar, .player-controls-progress-bar,
                        .player-control-play-pause-icon) {
                        display: none !important;
                        visibility: hidden !important;
                    }
                `;
                window.addEventListener('message', event => {
                    if (event.source !== window.parent || event.origin !== 'https://com.lofimen.app') return;
                    if (typeof event.data?.lofiInteractive !== 'boolean') return;
                    document.documentElement.dataset.lofiInteractive = String(event.data.lofiInteractive);
                    if (!event.data.lofiInteractive) {
                        // YouTube's compact quality picker uses a separate bottom sheet.
                        // Dismiss it before returning the same player to a background.
                        document.querySelectorAll('.close-button').forEach(button => button.click());
                    }
                });
                if (document.documentElement) {
                    document.documentElement.appendChild(style);
                } else {
                    const observer = new MutationObserver(() => {
                        if (!document.documentElement) return;
                        document.documentElement.appendChild(style);
                        observer.disconnect();
                    });
                    observer.observe(document, { childList: true });
                }
            }
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let handler = RadioMessageHandler()
        configuration.userContentController.add(handler, name: "radio")
        #if DEBUG
        if DebugTools.requested {
            configuration.userContentController.addUserScript(WKUserScript(source: """
                if (location.hostname === 'www.youtube.com') {
                    window.webkit.messageHandlers.radio.postMessage({debugFrame: true});
                }
                """, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        }
        #endif
        let webView = WKWebView(frame: .zero, configuration: configuration)
        handler.player = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.isInspectable = _isDebugAssertConfiguration()
        return webView
    }

    var statusText: String {
        if error != nil { return "Connection needs a moment" }
        if isLoading { return "Tuning in…" }
        return isPlaying ? "Live from Lofi Girl" : "A little calm, whenever you need it"
    }

    func toggle() {
        if wantsPlayback { pause() } else { play() }
    }

    func play() {
        if !wantsPlayback {
            reconnectAttempts = 0
            resetPlaybackProgress()
        }
        wantsPlayback = true
        if !hasLoaded || error != nil { load() }
        else if isReady { evaluate("radioPlay()") }
    }

    func pause() {
        wantsPlayback = false
        loadTimeout?.cancel()
        evaluate("radioPause()")
        isPlaying = false
        isLoading = false
    }

    func select(_ station: RadioStation) {
        guard self.station != station else { play(); return }
        let resume = wantsPlayback
        pause()
        self.station = station
        defaults.set(station.rawValue, forKey: "radio.station")
        // Selecting artwork before first playback should not launch WebKit.
        if hasLoaded {
            webView.loadHTMLString("<html style='background:transparent'></html>", baseURL: nil)
        }
        hasLoaded = false
        isReady = false
        error = nil
        loadID = UUID().uuidString
        if resume { play() }
    }

    func retry() {
        reconnectAttempts = 0
        wantsPlayback = true
        load()
    }

    func toggleMute() {
        if volume > 0 { previousVolume = volume; volume = 0 }
        else { volume = previousVolume }
    }

    private func load() {
        guard let url = AppResources.bundle.url(forResource: "player", withExtension: "html"),
              let template = try? String(contentsOf: url, encoding: .utf8) else {
            fail("The radio player couldn't load. Please rebuild the app.")
            return
        }
        error = nil
        isLoading = true
        isPlaying = false
        isReady = false
        hasLoaded = true
        resetPlaybackProgress()
        loadID = UUID().uuidString
        #if DEBUG
        diagnosticFrame = nil
        #endif
        let html = template.replacingOccurrences(of: "__VIDEO_ID__", with: station.videoID)
            .replacingOccurrences(of: "__VOLUME__", with: String(Int(volume * 100)))
            .replacingOccurrences(of: "__LOAD_ID__", with: loadID)
        // A stable HTTPS base URL supplies the referrer required by YouTube embeds.
        webView.loadHTMLString(html, baseURL: URL(string: "https://com.lofimen.app"))
        loadTimeout?.cancel()
        loadTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, self.isLoading else { return }
            self.fail("The stream is taking a little longer. Check your connection and try again.")
        }
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any],
              message["loadID"] as? String == loadID,
              let type = message["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            evaluate("radioInteractive(\(surfaces.isInteractive))")
            evaluate(wantsPlayback ? "radioPlay()" : "radioPause()")
        case "state":
            guard let state = message["value"] as? Int else { return }
            trace("YouTube state \(state), requested: \(wantsPlayback), interactive: \(acceptsVideoInput)")
            if state == 1 {
                // A delayed playing event must not undo an explicit native pause.
                if !wantsPlayback {
                    guard acceptsVideoInput else { evaluate("radioPause()"); return }
                    wantsPlayback = true
                }
                isPlaying = true
                isLoading = false
                error = nil
                loadTimeout?.cancel()
            } else if state == 2 || state == 0 {
                isPlaying = false
                // Only the interactive video can receive a direct user pause.
                // Background pauses keep the listening intent so the monitor can resume.
                if state == 2 && acceptsVideoInput { wantsPlayback = false }
                isLoading = wantsPlayback
                if !wantsPlayback { loadTimeout?.cancel() }
            } else if state == 3 {
                isLoading = wantsPlayback
            }
        case "blocked":
            trace("YouTube blocked autoplay")
            loadTimeout?.cancel()
            isLoading = false
            wantsPlayback = false
            error = "Press play in the video to let YouTube start the stream."
        case "error":
            let code = String(describing: message["value"] ?? "unknown")
            fail(code == "100" || code == "101" || code == "150"
                 ? "This stream is unavailable right now. Try another station."
                 : "Couldn't connect to YouTube (\(code)). Try tuning in again.")
        default: break
        }
    }

    private func evaluate(_ script: String) {
        guard isReady else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private var acceptsVideoInput: Bool {
        guard surfaces.isInteractive, let surface = surfaces.activeSurface else { return false }
        return surface.window?.isVisible == true && surface.window?.isMiniaturized != true && !surface.isHiddenOrHasHiddenAncestor
    }

    private func updatePlaybackActivity() {
        playbackMonitor?.cancel()
        playbackMonitor = nil
        // The player can be detached when SwiftUI destroys a closed panel. Keep its
        // live-stream JS scheduled, and prevent App Nap only while listening.
        webView.configuration.preferences.inactiveSchedulingPolicy = wantsPlayback ? .none : .suspend
        if wantsPlayback {
            playbackActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Playing Lofitime radio")
            playbackMonitor = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) }
                    catch { return }
                    await self?.checkPlayback()
                }
            }
        } else if let playbackActivity {
            ProcessInfo.processInfo.endActivity(playbackActivity)
            self.playbackActivity = nil
        }
    }

    private func resetPlaybackProgress() {
        lastPlaybackPosition = nil
        lastPlaybackProgress = Date()
        attemptedResume = false
    }

    private func checkPlayback() async {
        guard wantsPlayback, isReady else { return }
        let expectedLoad = loadID
        do {
            let result = try await webView.evaluateJavaScript("radioPlaybackStatus()")
            guard !Task.isCancelled, wantsPlayback, loadID == expectedLoad,
                  let status = result as? [String: Any], let state = status["state"] as? Int else { return }
            if state == 1, let position = status["time"] as? Double,
               lastPlaybackPosition.map({ abs(position - $0) > 0.1 }) ?? true {
                if lastPlaybackPosition != nil { reconnectAttempts = 0 }
                lastPlaybackPosition = position
                lastPlaybackProgress = Date()
                attemptedResume = false
            } else if [0, 2, -1, 5].contains(state), !attemptedResume {
                // Resume first; a reconnect is only needed if the stream remains stuck.
                attemptedResume = true
                trace("Resuming state \(state); window attached: \(webView.window != nil)")
                evaluate("radioPlay()")
            }
            if Date().timeIntervalSince(lastPlaybackProgress) >= 30 { reconnect() }
        } catch {
            guard !Task.isCancelled, wantsPlayback, loadID == expectedLoad else { return }
            reconnect()
        }
    }

    private func reconnect() {
        guard wantsPlayback, reconnectAttempts < 2 else {
            fail("The stream lost its connection. Check your connection and try again.")
            return
        }
        reconnectAttempts += 1
        trace("Reconnecting stream (attempt \(reconnectAttempts))")
        load()
    }

    private func trace(_ message: String) {
        #if DEBUG
        if DebugTools.requested, ProcessInfo.processInfo.environment["LOFI_PLAYBACK_TRACE"] == "1" {
            print("\(Date().formatted(.iso8601)) · \(message)")
            fflush(stdout)
        }
        #endif
    }

    private func fail(_ message: String) {
        loadTimeout?.cancel()
        isLoading = false
        isPlaying = false
        wantsPlayback = false
        error = message
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        fail("You're a little out of range. Check your connection and try again.")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        fail("The connection was interrupted. Try tuning in again.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isReady = false
        if wantsPlayback { reconnect() }
        else { fail("The player needs a fresh start. Tune in again.") }
    }

    deinit {
        loadTimeout?.cancel()
        playbackMonitor?.cancel()
        if let playbackActivity { ProcessInfo.processInfo.endActivity(playbackActivity) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}
