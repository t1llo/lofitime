import AppKit
import SwiftUI
import WebKit

enum VideoPresentation: Int {
    case studio = 0, menuBar = 1, quality = 2
}

enum VideoGeometry {
    static let chromeInset: CGFloat = 96

    static func frame(in size: CGSize, fill: Bool, focalPoint: CGFloat, presentation: VideoPresentation = .studio) -> CGRect {
        let ratio: CGFloat = 16 / 9
        // Also crop the stream's baked-in track labels at the video edges; hiding
        // YouTube's HTML title alone cannot remove text inside the live picture.
        let zoom: CGFloat = presentation == .menuBar ? 1.45 : 1.3
        let width = fill ? max(size.width, size.height * ratio) * zoom : min(size.width, size.height * ratio)
        let height = width / ratio
        let x = fill ? min(0, max(size.width - width, size.width / 2 - width * focalPoint)) : (size.width - width) / 2
        return CGRect(x: x, y: (size.height - height) / 2, width: width, height: height)
    }

    static func playerFrame(in size: CGSize, fill: Bool, focalPoint: CGFloat, presentation: VideoPresentation = .studio) -> CGRect {
        let video = frame(in: size, fill: fill, focalPoint: focalPoint, presentation: presentation)
        // YouTube letterboxes the 16:9 video inside this taller player. Its title and
        // transport controls land in the clipped margins, preserving the video framing.
        return fill ? video.insetBy(dx: 0, dy: -chromeInset) : video
    }
}

/// Moves the same live player between visible windows, without a second stream or a reload.
@MainActor
final class VideoSurfaceRouter {
    private struct WeakSurface { weak var value: VideoSurfaceView? }
    private let webView: WKWebView
    private var surfaces: [WeakSurface] = []
    private(set) weak var activeSurface: VideoSurfaceView?
    private(set) var isInteractive = false

    init(webView: WKWebView) { self.webView = webView }

    func register(_ surface: VideoSurfaceView) {
        surfaces.removeAll { $0.value == nil || $0.value === surface }
        surfaces.append(WeakSurface(value: surface))
        refresh()
    }

    func unregister(_ surface: VideoSurfaceView) {
        surfaces.removeAll { $0.value == nil || $0.value === surface }
        refresh()
    }

    func refresh() {
        surfaces.removeAll { $0.value == nil }
        let visible = surfaces.compactMap(\.value).filter {
            $0.window?.isVisible == true && $0.window?.isMiniaturized != true && !$0.isHiddenOrHasHiddenAncestor
        }
        guard let destination = visible.max(by: { $0.presentation.rawValue < $1.presentation.rawValue }) else {
            // Leave the player attached to its current host for background audio.
            return
        }
        if webView.superview !== destination {
            webView.removeFromSuperview()
            destination.addSubview(webView)
            activeSurface = destination
        }
        destination.layoutPlayer(webView)
        let interactive = !destination.fillsBounds
        if isInteractive != interactive {
            isInteractive = interactive
            webView.evaluateJavaScript("radioInteractive(\(interactive))", completionHandler: nil)
        }
    }
}

@MainActor
final class VideoSurfaceView: NSView {
    let presentation: VideoPresentation
    weak var router: VideoSurfaceRouter?
    var fillsBounds = true
    var focalPoint: CGFloat = 0.65
    private var windowObservers: [NSObjectProtocol] = []

    init(router: VideoSurfaceRouter, presentation: VideoPresentation) {
        self.router = router
        self.presentation = presentation
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        router.register(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.scheduleRefresh() }
                })
            }
        }
        scheduleRefresh()
    }

    override func layout() {
        super.layout()
        if let webView = subviews.first as? WKWebView { layoutPlayer(webView) }
    }

    func layoutPlayer(_ webView: WKWebView) {
        guard webView.superview === self else { return }
        let frame = VideoGeometry.playerFrame(in: bounds.size, fill: fillsBounds, focalPoint: focalPoint, presentation: presentation)
        if webView.frame != frame { webView.frame = frame }
    }

    private func scheduleRefresh() {
        DispatchQueue.main.async { [weak self] in self?.router?.refresh() }
    }

    func detach() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        router?.unregister(self)
    }

    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }
}

struct RadioWebView: NSViewRepresentable {
    let player: RadioPlayer
    var presentation: VideoPresentation = .studio
    var fillsBounds = true

    func makeNSView(context: Context) -> VideoSurfaceView {
        VideoSurfaceView(router: player.surfaces, presentation: presentation)
    }

    func updateNSView(_ nsView: VideoSurfaceView, context: Context) {
        nsView.fillsBounds = fillsBounds
        nsView.focalPoint = player.station.focalPoint
        nsView.needsLayout = true
        player.surfaces.refresh()
    }

    static func dismantleNSView(_ nsView: VideoSurfaceView, coordinator: ()) { nsView.detach() }
}

struct VideoBackdrop: View {
    var player: RadioPlayer
    let presentation: VideoPresentation
    var fillsBounds = true

    var body: some View {
        GeometryReader { geometry in
            Color.black.overlay(alignment: .topLeading) {
                artwork(in: geometry.size)
            }.overlay {
                RadioWebView(player: player, presentation: presentation, fillsBounds: fillsBounds)
                    .allowsHitTesting(!fillsBounds)
            }.overlay(alignment: .topLeading) {
                // Paused/loading players can show centered YouTube overlays. Cover those
                // with station artwork while keeping the live WebView mounted underneath.
                if fillsBounds && (!player.isPlaying || player.isLoading) {
                    Color.black.overlay(alignment: .topLeading) {
                        artwork(in: geometry.size)
                    }.allowsHitTesting(false)
                }
            }.contentShape(Rectangle()).clipped()
        }
    }

    @ViewBuilder private func artwork(in size: CGSize) -> some View {
        if let image = AppResources.artwork(player.station) {
            let frame = VideoGeometry.frame(in: size, fill: fillsBounds, focalPoint: player.station.focalPoint, presentation: presentation)
            Image(nsImage: image).resizable()
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
    }
}
