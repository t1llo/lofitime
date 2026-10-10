import AppKit
import LofiMenCore
import SceneKit
import SwiftUI

struct RoomCameraState: Equatable {
    var zoom = 1.0
    var pan = CGSize.zero
    var yaw = 0.0
    var pitch = 0.0
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
        view.setAccessibilityHelp("Scroll or pinch to zoom, drag to move, Option-drag or right-drag to tilt, double-click to reset. Keyboard: plus and minus to zoom, arrows to move, Option-arrows to tilt, zero to reset.")
        view.updateDesktop(desktop)
        if !view.isInteracting { view.cameraState = camera }
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
        private(set) var isInteracting = false
        private(set) var desktopHost: NSHostingView<AnyView>?
        private var transitionID = 0
        private var fittedState: RoomCameraState?
        private var fittedSize = CGSize.zero
        private var dragPoint: NSPoint?
        private var tilting = false
        private var interactionTimer: Timer?
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
            endInteraction()
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
                // Frame the default view once; tilting must not also change the zoom scale.
                destination.position = SCNVector3(5.4, 4.4, 12)
                destination.look(at: SCNVector3(0, 1.85, 0))
                let corners = [-4.4, 4.4].flatMap { x in
                    [-0.3, 4.25].flatMap { y in [-2.35, 2.35].map { z in destination.convertPosition(SCNVector3(x, y, z), from: nil) } }
                }
                let width = corners.map(\.x).max()! - corners.map(\.x).min()!
                let height = corners.map(\.y).max()! - corners.map(\.y).min()!
                scale = max(height / 2, width / (bounds.width / bounds.height) / 2) * 1.035 / cameraState.zoom
                let horizontalRadius: Double = hypot(5.4, 12)
                let radius: Double = hypot(horizontalRadius, 2.55)
                let azimuth = atan2(5.4, 12) + cameraState.yaw
                let elevation = asin(2.55 / radius) + cameraState.pitch
                destination.position = SCNVector3(radius * cos(elevation) * sin(azimuth),
                                                  1.85 + radius * sin(elevation),
                                                  radius * cos(elevation) * cos(azimuth))
                destination.look(at: SCNVector3(0, 1.85, 0))
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
            SCNTransaction.disableActions = !animate
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
            let animate = visible && (isTransitioning || isInteracting || (hasAnimation && !showsStats && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
            preferredFramesPerSecond = isTransitioning || isInteracting ? 60 : 24
            isPlaying = animate
            scene?.isPaused = !animate
        }

        private func change(_ state: RoomCameraState) {
            guard !showsStats, !isTransitioning else { return }
            cameraState = state
            cameraState.zoom = min(3.5, max(0.85, cameraState.zoom))
            cameraState.yaw = min(0.35, max(-0.35, cameraState.yaw))
            cameraState.pitch = min(0.22, max(-0.14, cameraState.pitch))
            let explored = 1 - 1 / max(1, cameraState.zoom)
            let panWidth = 0.6 + 3.8 * explored
            let panHeight = 0.4 + 2.5 * explored
            cameraState.pan.width = min(panWidth, max(-panWidth, cameraState.pan.width))
            cameraState.pan.height = min(panHeight, max(-panHeight, cameraState.pan.height))
            beginInteraction()
            fitCamera()
            changeCamera?(cameraState)
        }

        override func scrollWheel(with event: NSEvent) {
            guard !showsStats, event.momentumPhase.isEmpty else { return }
            let delta = max(-60, min(60, event.scrollingDeltaY))
            zoom(by: exp(delta * (event.hasPreciseScrollingDeltas ? 0.004 : 0.07)),
                 at: convert(event.locationInWindow, from: nil))
        }

        override func magnify(with event: NSEvent) {
            zoom(by: exp(Double(event.magnification)), at: convert(event.locationInWindow, from: nil))
        }

        func zoom(by factor: Double, at point: NSPoint) {
            guard factor.isFinite, factor > 0, bounds.height > 0 else { return }
            var state = cameraState
            state.zoom = min(3.5, max(0.85, state.zoom * factor))
            guard state.zoom != cameraState.zoom else { return }
            let oldScale = pointOfView?.camera?.orthographicScale ?? 1
            let newScale = oldScale * cameraState.zoom / state.zoom
            // Keep the room point under the pointer still while changing magnification.
            let anchor = bounds.contains(point) ? point : NSPoint(x: bounds.midX, y: bounds.midY)
            state.pan.width += (anchor.x - bounds.midX) * (oldScale - newScale) * 2 / bounds.height
            state.pan.height += (anchor.y - bounds.midY) * (oldScale - newScale) * 2 / bounds.height * (isFlipped ? -1 : 1)
            change(state)
        }

        override func mouseDown(with event: NSEvent) {
            guard !showsStats, !isTransitioning else { return }
            window?.makeFirstResponder(self)
            if event.clickCount == 2 { change(RoomCameraState()); dragPoint = nil }
            else {
                tilting = event.modifierFlags.contains(.option) || event.type == .rightMouseDown
                dragPoint = convert(event.locationInWindow, from: nil)
                (tilting ? NSCursor.crosshair : NSCursor.closedHand).set()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !showsStats, let previous = dragPoint, bounds.height > 0 else { return }
            let point = convert(event.locationInWindow, from: nil)
            let units = (pointOfView?.camera?.orthographicScale ?? 1) * 2 / bounds.height
            var state = cameraState
            if tilting {
                state.yaw -= (point.x - previous.x) * 0.004
                state.pitch += (point.y - previous.y) * 0.003 * (isFlipped ? -1 : 1)
            } else {
                state.pan.width -= (point.x - previous.x) * units
                state.pan.height -= (point.y - previous.y) * units * (isFlipped ? -1 : 1)
            }
            dragPoint = point
            change(state)
        }

        override func mouseUp(with event: NSEvent) { dragPoint = nil; if !showsStats { NSCursor.openHand.set() } }
        override func rightMouseDown(with event: NSEvent) { mouseDown(with: event) }
        override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
        override func rightMouseUp(with event: NSEvent) { mouseUp(with: event) }
        override func resetCursorRects() { if !showsStats { addCursorRect(bounds, cursor: .openHand) } }

        override func keyDown(with event: NSEvent) {
            guard !showsStats else { super.keyDown(with: event); return }
            var state = cameraState
            switch event.keyCode {
            case 123: if event.modifierFlags.contains(.option) { state.yaw -= 0.05 } else { state.pan.width -= 0.25 }
            case 124: if event.modifierFlags.contains(.option) { state.yaw += 0.05 } else { state.pan.width += 0.25 }
            case 125: if event.modifierFlags.contains(.option) { state.pitch -= 0.04 } else { state.pan.height -= 0.25 }
            case 126: if event.modifierFlags.contains(.option) { state.pitch += 0.04 } else { state.pan.height += 0.25 }
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

        private func beginInteraction() {
            interactionTimer?.invalidate()
            isInteracting = true
            updateAnimation()
            let timer = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.endInteraction() }
            }
            interactionTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func endInteraction() {
            interactionTimer?.invalidate()
            interactionTimer = nil
            isInteracting = false
            updateAnimation()
        }

        func stopObserving() {
            endInteraction()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
            motionObserver = nil
        }

        deinit {
            interactionTimer?.invalidate()
            observers.forEach(NotificationCenter.default.removeObserver)
            if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        }
    }
}
