import AppKit
import LofiMenCore
import SceneKit
import SwiftUI

struct RoomCameraState: Equatable {
    var zoom = 1.0
    var pan = CGSize.zero
}

struct StudyRoomScene: NSViewRepresentable {
    let growth: FocusRoom
    let theme: RoomTheme
    @Binding var camera: RoomCameraState
    var showsStats = false
    var desktop: AnyView?

    func makeNSView(context: Context) -> RoomView {
        let view = RoomView()
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = false
        view.allowsCameraControl = false
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityIdentifier("activity-room")
        return view
    }

    func updateNSView(_ view: RoomView, context: Context) {
        view.changeCamera = { camera = $0 }
        let signature = "\(growth.visualStep)-\(NSColor(theme.background).description)"
        if view.signature != signature {
            view.signature = signature
            view.backgroundColor = NSColor(theme.surface)
            view.scene = StudyRoomBuilder.scene(growth: growth, theme: theme)
            view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
            view.hasAnimation = growth.nourishment > 0
            view.invalidateCamera()
        }
        view.setAccessibilityLabel("Side-view study room. \(growth.title). \(growth.additions.map(\.title).joined(separator: ", ")). \(growth.bookCount) books. \(focusTime(growth.recentDuration)) focused in the last seven days.")
        view.setAccessibilityHelp("Scroll or pinch to zoom, drag to explore, double-click to reset. Keyboard: plus and minus to zoom, arrows to move, zero to reset.")
        view.updateDesktop(desktop)
        view.cameraState = camera
        view.setShowsStats(showsStats)
        view.fitCamera()
        view.updateAnimation()
    }

    static func dismantleNSView(_ view: RoomView, coordinator: ()) {
        view.stopObserving()
        view.cancelTransition()
        view.isPlaying = false
        view.scene = nil
    }

    final class RoomView: SCNView {
        var signature = ""
        var hasAnimation = false
        var cameraState = RoomCameraState()
        var changeCamera: ((RoomCameraState) -> Void)?
        private(set) var showsStats = false
        private(set) var isTransitioning = false
        private(set) var desktopHost: NSHostingView<AnyView>?
        private var transitionID = 0
        private var fittedState: RoomCameraState?
        private var fittedSize = CGSize.zero
        private var dragPoint: NSPoint?
        private var observers: [NSObjectProtocol] = []
        private var motionObserver: NSObjectProtocol?

        override var acceptsFirstResponder: Bool { true }

        override func accessibilityChildren() -> [Any]? {
            guard showsStats, !isTransitioning, let desktopHost, !desktopHost.isHidden else { return [] }
            return [desktopHost]
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                             NSWindow.didDeminiaturizeNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        Task { @MainActor in self?.updateAnimation() }
                    })
                }
                motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
                ) { [weak self] _ in Task { @MainActor in self?.updateAnimation() } }
            }
            updateAnimation()
        }

        override func layout() { super.layout(); fitCamera(); positionDesktop(); updateAnimation() }
        override func viewDidHide() { super.viewDidHide(); updateAnimation() }
        override func viewDidUnhide() { super.viewDidUnhide(); updateAnimation() }

        func updateDesktop(_ content: AnyView?) {
            guard let content else { return }
            if let desktopHost { desktopHost.rootView = content }
            else {
                let host = NSHostingView(rootView: content)
                host.sizingOptions = []
                host.isHidden = true
                host.wantsLayer = true
                host.layer?.masksToBounds = true
                desktopHost = host
                addSubview(host)
            }
        }

        func invalidateCamera() { fittedState = nil }

        func setShowsStats(_ value: Bool) {
            guard value != showsStats else { return }
            showsStats = value
            dragPoint = nil
            if let desktopHost {
                // Cross-fade out while the camera pulls back through the monitor.
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
                    desktopHost.animator().alphaValue = 0
                }
            }
            invalidateCamera()
            fitCamera(animated: window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            window?.invalidateCursorRects(for: self)
        }

        func fitCamera(animated: Bool = false) {
            guard let camera = pointOfView, bounds.width > 0, bounds.height > 0,
                  fittedState != cameraState || fittedSize != bounds.size else { return }
            fittedState = cameraState
            fittedSize = bounds.size
            let destination = SCNNode()
            let scale: Double
            if showsStats, let screen = scene?.rootNode.childNode(withName: "desktop-screen", recursively: true) {
                let center = screen.convertPosition(SCNVector3(0, 0, 0.006), to: nil)
                destination.position = SCNVector3(center.x, center.y, center.z + 1.4)
                // Travel all the way into the screen. It covers the viewport before the
                // native statistics page appears, so its text never needs a 3D transform.
                scale = min(0.49, 0.84 / (bounds.width / bounds.height)) / 2.16
            } else {
                destination.position = SCNVector3(5.4, 4.4, 12)
                destination.look(at: SCNVector3(0, 1.85, 0))
                let corners = [-4.4, 4.4].flatMap { x in
                    [-0.3, 4.25].flatMap { y in [-2.35, 2.35].map { z in destination.convertPosition(SCNVector3(x, y, z), from: nil) } }
                }
                let width = corners.map(\.x).max()! - corners.map(\.x).min()!
                let height = corners.map(\.y).max()! - corners.map(\.y).min()!
                scale = max(height / 2, width / (bounds.width / bounds.height) / 2) * 1.035 / cameraState.zoom
                let delta = destination.convertVector(SCNVector3(cameraState.pan.width, cameraState.pan.height, 0), to: nil)
                destination.position = SCNVector3(destination.position.x + delta.x, destination.position.y + delta.y, destination.position.z + delta.z)
            }

            // SwiftUI lays out the pane again when the room footer disappears. An empty
            // transaction would complete immediately and pause a still-moving camera.
            guard !SCNMatrix4EqualToMatrix4(camera.transform, destination.transform)
                    || abs((camera.camera?.orthographicScale ?? 0) - scale) > 0.0001 else {
                positionDesktop()
                return
            }
            transitionID += 1
            let id = transitionID
            let animate = (animated || isTransitioning) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            isTransitioning = animate
            updateAnimation()
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animate ? 0.8 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if animate {
                SCNTransaction.completionBlock = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.transitionID == id else { return }
                        self.isTransitioning = false
                        self.positionDesktop()
                        self.updateAnimation()
                    }
                }
            }
            camera.transform = destination.transform
            camera.camera?.orthographicScale = scale
            SCNTransaction.commit()
            positionDesktop()
            needsDisplay = true
        }

        private func positionDesktop() {
            guard let host = desktopHost else { return }
            host.frame = bounds
            guard !isTransitioning else { return }
            guard showsStats else {
                host.isHidden = true
                host.alphaValue = 0
                return
            }
            let appearing = host.isHidden || host.alphaValue == 0
            host.isHidden = false
            if appearing {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
                    host.animator().alphaValue = 1
                }
            }
        }

        func updateAnimation() {
            let visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
                && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
            let animate = visible && (isTransitioning || (hasAnimation && !showsStats && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
            preferredFramesPerSecond = isTransitioning ? 60 : 24
            isPlaying = animate
            scene?.isPaused = !animate
        }

        private func change(_ state: RoomCameraState) {
            guard !showsStats, !isTransitioning else { return }
            cameraState = state
            cameraState.zoom = min(3.5, max(1, cameraState.zoom))
            cameraState.pan.width = min(3.8, max(-3.8, cameraState.pan.width))
            cameraState.pan.height = min(2.5, max(-2.5, cameraState.pan.height))
            fitCamera()
            changeCamera?(cameraState)
        }

        override func scrollWheel(with event: NSEvent) {
            guard !showsStats else { return }
            var state = cameraState
            state.zoom *= exp(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.012 : 0.09))
            change(state)
        }

        override func magnify(with event: NSEvent) {
            var state = cameraState
            state.zoom *= 1 + Double(event.magnification)
            change(state)
        }

        override func mouseDown(with event: NSEvent) {
            guard !showsStats else { return }
            window?.makeFirstResponder(self)
            if event.clickCount == 2 { change(RoomCameraState()); dragPoint = nil }
            else { dragPoint = convert(event.locationInWindow, from: nil); NSCursor.closedHand.set() }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !showsStats, let previous = dragPoint, bounds.height > 0 else { return }
            let point = convert(event.locationInWindow, from: nil)
            let units = (pointOfView?.camera?.orthographicScale ?? 1) * 2 / bounds.height
            var state = cameraState
            state.pan.width -= (point.x - previous.x) * units
            state.pan.height -= (point.y - previous.y) * units * (isFlipped ? -1 : 1)
            dragPoint = point
            change(state)
        }

        override func mouseUp(with event: NSEvent) { dragPoint = nil; if !showsStats { NSCursor.openHand.set() } }
        override func resetCursorRects() { if !showsStats { addCursorRect(bounds, cursor: .openHand) } }

        override func keyDown(with event: NSEvent) {
            guard !showsStats else { super.keyDown(with: event); return }
            var state = cameraState
            switch event.keyCode {
            case 123: state.pan.width -= 0.25
            case 124: state.pan.width += 0.25
            case 125: state.pan.height -= 0.25
            case 126: state.pan.height += 0.25
            default:
                switch event.charactersIgnoringModifiers {
                case "+", "=": state.zoom *= 1.2
                case "-": state.zoom /= 1.2
                case "0": state = RoomCameraState()
                default: super.keyDown(with: event); return
                }
            }
            change(state)
        }

        func cancelTransition() { transitionID += 1; isTransitioning = false }

        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
            motionObserver = nil
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
            if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        }
    }
}
