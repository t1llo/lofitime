import AppKit
import LofiMenCore
import ModelIO
import SceneKit
import SceneKit.ModelIO
import SwiftUI

struct FocusGarden: View {
    @Environment(\.roomTheme) private var theme
    let activity: FocusActivity
    @Binding var selectedDay: Date?
    @State private var zoom = 1.0

    var body: some View {
        GardenSceneView(weeks: activity.gardenWeeks, selectedDay: selectedDay, theme: theme, zoom: $zoom) { date in
            selectedDay = selectedDay == date ? nil : date
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GardenSceneView: NSViewRepresentable {
    let weeks: [GardenWeek]
    let selectedDay: Date?
    let theme: RoomTheme
    @Binding var zoom: Double
    let select: (Date) -> Void

    func makeNSView(context: Context) -> GardenView {
        let view = GardenView()
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 24
        view.backgroundColor = NSColor(theme.background)
        view.allowsCameraControl = false
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("\(FocusActivity.historyWeeks) full weeks of daily forest squares. Hover for focus time, click for sessions, scroll to zoom and drag to pan.")
        view.setAccessibilityIdentifier("activity-forest")
        return view
    }

    func updateNSView(_ view: GardenView, context: Context) {
        view.select = select
        view.days = weeks.flatMap(\.days).filter(\.isInRange)
        view.changeZoom = { zoom = $0 }
        let signature = NSColor(theme.background).description + weeks.flatMap(\.days).map { "\($0.date.timeIntervalSince1970):\($0.duration):\($0.isInRange)" }.joined(separator: "|")
        if view.signature != signature {
            view.signature = signature
            view.hideHover()
            view.backgroundColor = NSColor(theme.background)
            view.scene = GardenBuilder.scene(weeks: weeks, theme: theme)
            view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
            view.hasAnimation = weeks.flatMap(\.days).contains { $0.hasHive || $0.hasFox }
            view.updateAnimation()
        }
        view.zoom = zoom
        view.weekCount = weeks.count
        view.fitCamera()
        if zoom == 1 { view.pointOfView?.position = SCNVector3(0, 16, 10) }
        for day in weeks.flatMap(\.days) {
            view.scene?.rootNode.childNode(withName: "selection-\(day.date.timeIntervalSince1970)", recursively: true)?.isHidden = day.date != selectedDay
        }
    }

    static func dismantleNSView(_ view: GardenView, coordinator: ()) {
        view.stopObservingWindow()
        view.isPlaying = false
        view.scene = nil
    }

    final class GardenView: SCNView {
        var signature = ""
        var hasAnimation = false
        private var windowObservers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObservingWindow()
            if let window {
                windowObservers.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.updateAnimation() }
                })
            }
            updateAnimation()
        }

        override func viewDidHide() {
            super.viewDidHide()
            updateAnimation()
        }

        override func viewDidUnhide() {
            super.viewDidUnhide()
            updateAnimation()
        }

        func updateAnimation() {
            let visible = window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
            isPlaying = hasAnimation && visible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        func stopObservingWindow() {
            windowObservers.forEach(NotificationCenter.default.removeObserver)
            windowObservers = []
        }

        deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }

        var select: ((Date) -> Void)?
        var changeZoom: ((Double) -> Void)?
        var zoom = 1.0
        var weekCount = FocusActivity.historyWeeks
        var fittedScale = 3.0
        var days: [ActivityDay] = []
        private var start: NSPoint?
        private var dragged = false
        private var hoverTracking: NSTrackingArea?
        private let hoverCard = HoverCard()
        override func layout() {
            super.layout()
            fitCamera()
        }
        func fitCamera() {
            guard bounds.width > 0, bounds.height > 0 else { return }
            // Fit the actual calendar, not an oversized landscape. Weekdays run
            // across the map so each day has room for its low-poly details.
            let aspect = bounds.width / bounds.height
            let width: CGFloat = 7.4
            let height = CGFloat(weekCount) * 1.06 * 0.848 + 0.55
            fittedScale = max(height / 2, width / aspect / 2) * 1.02
            pointOfView?.camera?.orthographicScale = fittedScale / zoom
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTracking { removeTrackingArea(hoverTracking) }
            let tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(tracking)
            hoverTracking = tracking
        }
        override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
        override func mouseMoved(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            guard let day = day(at: location) else { hideHover(); return }
            if hoverCard.superview == nil { addSubview(hoverCard) }
            hoverCard.show(day)
            let size = hoverCard.frame.size
            hoverCard.setFrameOrigin(NSPoint(
                x: min(max(8, location.x + 14), max(8, bounds.width - size.width - 8)),
                y: min(max(8, location.y + 14), max(8, bounds.height - size.height - 8))))
            hoverCard.isHidden = false
        }
        override func mouseExited(with event: NSEvent) { hideHover() }
        func hideHover() { hoverCard.isHidden = true }

        func day(at location: NSPoint) -> ActivityDay? {
            for hit in hitTest(location, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("day-"), let timestamp = Double(name.dropFirst(4)) {
                        return days.first { $0.date.timeIntervalSince1970 == timestamp }
                    }
                    node = current.parent
                }
            }
            return nil
        }

        final class HoverCard: NSView {
            private let dateLabel = NSTextField(labelWithString: "")
            private let durationLabel = NSTextField(labelWithString: "")

            init() {
                super.init(frame: .zero)
                wantsLayer = true
                layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
                layer?.cornerRadius = 10
                dateLabel.font = .systemFont(ofSize: 11)
                dateLabel.textColor = .white.withAlphaComponent(0.75)
                durationLabel.font = .systemFont(ofSize: 13, weight: .semibold)
                durationLabel.textColor = .white
                addSubview(dateLabel)
                addSubview(durationLabel)
                isHidden = true
                setAccessibilityIdentifier("activity-day-hover")
            }

            required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

            func show(_ day: ActivityDay) {
                dateLabel.stringValue = day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                durationLabel.stringValue = "\(SessionDuration.summary(day.duration)) focused"
                dateLabel.sizeToFit()
                durationLabel.sizeToFit()
                let width = max(dateLabel.frame.width, durationLabel.frame.width) + 24
                frame.size = NSSize(width: width, height: 58)
                dateLabel.setFrameOrigin(NSPoint(x: 12, y: 34))
                durationLabel.setFrameOrigin(NSPoint(x: 12, y: 12))
            }

            // The tooltip must not interrupt hovering, tile selection, or panning.
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
        }
        override func accessibilityChildren() -> [Any]? {
            days.map { day in
                let element = DayElement()
                element.setAccessibilityParent(self)
                element.setAccessibilityRole(.button)
                element.setAccessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(SessionDuration.summary(day.duration)) focused")
                element.setAccessibilityIdentifier("activity-day-\(day.date.timeIntervalSince1970)")
                element.press = { [weak self] in self?.select?(day.date) }
                if let patch = scene?.rootNode.childNode(withName: "day-\(day.date.timeIntervalSince1970)", recursively: true), let window {
                    let projected = projectPoint(patch.position)
                    let size = bounds.height / (2 * fittedScale / zoom) * 0.94
                    let rect = NSRect(x: projected.x - size / 2, y: projected.y - size / 2, width: size, height: size)
                    element.setAccessibilityFrame(window.convertToScreen(convert(rect, to: nil)))
                }
                return element
            }
        }
        final class DayElement: NSAccessibilityElement {
            var press: (() -> Void)?
            override func accessibilityPerformPress() -> Bool { press?(); return true }
        }
        override func mouseDown(with event: NSEvent) {
            hideHover()
            start = convert(event.locationInWindow, from: nil)
            dragged = false
        }
        override func mouseDragged(with event: NSEvent) {
            hideHover()
            guard let previous = start else { return }
            let location = convert(event.locationInWindow, from: nil)
            if hypot(location.x - previous.x, location.y - previous.y) > 2 { dragged = true }
            if dragged, let camera = pointOfView {
                let factor = 2 * fittedScale / zoom / max(bounds.height, 1)
                camera.position.x -= (location.x - previous.x) * factor
                camera.position.z += (location.y - previous.y) * factor
                start = location
            }
        }
        override func scrollWheel(with event: NSEvent) {
            hideHover()
            changeZoom?(min(4, max(1, zoom * exp(Double(event.scrollingDeltaY) * 0.015))))
        }
        override func magnify(with event: NSEvent) {
            hideHover()
            changeZoom?(min(4, max(1, zoom * (1 + Double(event.magnification)))))
        }
        override func mouseUp(with event: NSEvent) {
            guard !dragged else { return }
            let location = convert(event.locationInWindow, from: nil)
            if let day = day(at: location) { select?(day.date) }
        }
    }
}

@MainActor enum GardenBuilder {
    private static var models: [String: SCNNode] = [:]

    static func tileColor(level: Int, theme: RoomTheme = .candlelight) -> NSColor {
        let colors = [NSColor(theme.elevated), color(0.83, 0.90, 0.73), color(0.69, 0.82, 0.56),
                      color(0.53, 0.73, 0.41), color(0.38, 0.62, 0.30)]
        return colors[min(4, max(0, level))]
    }

    static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }

    static func material(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = 0.9
        material.lightingModel = .physicallyBased
        return material
    }

    static func node(_ geometry: SCNGeometry, color: NSColor, at position: SCNVector3 = SCNVector3Zero) -> SCNNode {
        geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    static func model(_ name: String, height: Float) -> SCNNode {
        if models[name] == nil, let url = AppResources.bundle.url(forResource: name, withExtension: "obj", subdirectory: "Garden") {
            let asset = MDLAsset(url: url)
            let root = SCNNode()
            for index in 0..<asset.count { root.addChildNode(SCNNode(mdlObject: asset.object(at: index))) }
            root.enumerateChildNodes { child, _ in
                for material in child.geometry?.materials ?? [] {
                    material.lightingModel = .physicallyBased
                    material.roughness.contents = 1
                    material.isDoubleSided = true
                    if let name = material.name, name.lowercased().contains("grass") || name.lowercased().contains("leaf") {
                        material.diffuse.contents = color(0.39, 0.60, 0.34)
                    }
                }
            }
            models[name] = root
        }
        let copy = models[name]?.clone() ?? SCNNode()
        let bounds = copy.boundingBox
        let originalHeight = bounds.max.y - bounds.min.y
        if originalHeight > 0 {
            let scale = CGFloat(height) / originalHeight
            copy.scale = SCNVector3(scale, scale, scale)
            copy.position.y = -bounds.min.y * scale
        }
        return copy
    }

    static func scene(weeks: [GardenWeek], theme: RoomTheme = .candlelight) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor(theme.background)
        let root = scene.rootNode
        let camera = SCNNode()
        camera.name = "camera"
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 4.0
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 100
        camera.position = SCNVector3(0, 16, 10)
        camera.look(at: SCNVector3Zero)
        root.addChildNode(camera)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1_000
        sun.light?.color = color(1, 0.94, 0.80)
        sun.light?.castsShadow = true
        sun.light?.shadowRadius = 5
        sun.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        sun.light?.shadowColor = NSColor.black.withAlphaComponent(0.18)
        sun.eulerAngles = SCNVector3(-Float.pi / 3, -Float.pi / 5, 0)
        root.addChildNode(sun)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 450
        ambient.light?.color = color(0.84, 0.90, 1)
        root.addChildNode(ambient)

        let centerRow = Float(weeks.count - 1) / 2

        for week in weeks {
          for (row, day) in week.days.enumerated() {
            let flowers = day.flowers
            let bushes = day.bushes
            let trees = day.trees
            let hasHive = day.hasHive
            let hasFox = day.hasFox
            let seed = day.plantingSeed
            let patch = SCNNode()
            patch.name = day.isInRange ? "day-\(day.date.timeIntervalSince1970)" : "future-day"
            patch.position = SCNVector3(Float(row - 3) * 1.06, 0, (Float(week.index) - centerRow) * 1.06)
            root.addChildNode(patch)
            let turf = SCNBox(width: 0.94, height: 0.015, length: 0.94, chamferRadius: 0.025)
            let planting = node(turf, color: tileColor(level: day.level, theme: theme))
            planting.opacity = day.isInRange ? 1 : 0.45
            patch.addChildNode(planting)
            let ring = SCNNode()
            for side: CGFloat in [-1, 1] {
                ring.addChildNode(node(SCNBox(width: 0.98, height: 0.015, length: 0.025, chamferRadius: 0), color: color(0.72, 0.52, 0.25), at: SCNVector3(0, 0.025, side * 0.48)))
                ring.addChildNode(node(SCNBox(width: 0.025, height: 0.015, length: 0.98, chamferRadius: 0), color: color(0.72, 0.52, 0.25), at: SCNVector3(side * 0.48, 0.025, 0)))
            }
            ring.name = "selection-\(day.date.timeIntervalSince1970)"
            patch.addChildNode(ring)

            for index in 0..<(flowers > 0 ? 2 : 0) {
                let grass = model("grass", height: 0.10)
                place(grass, index: index, seed: seed, radius: 0.40)
                patch.addChildNode(grass)
            }
            let variants = ["flower_purpleA", "flower_yellowA", "flower_redA", "flower_purpleB"]
            for index in 0..<flowers {
                let flower = model(variants[(index + seed) % variants.count], height: 0.22 + Float(index % 3) * 0.035)
                place(flower, index: index, seed: seed + 21, radius: 0.35)
                patch.addChildNode(flower)
            }
            for index in 0..<bushes {
                let bush = model(index == 0 ? "plant_bushDetailed" : "plant_bushSmall", height: 0.25)
                bush.position = index == 0 ? SCNVector3(-0.28, 0, 0.12) : SCNVector3(0.28, 0, 0.22)
                bush.eulerAngles.y = CGFloat(seed % 6)
                patch.addChildNode(bush)
                if day.hasBerries {
                    for berry in 0..<5 {
                        let fruit = SCNSphere(radius: 0.045)
                        fruit.segmentCount = 6
                        bush.addChildNode(node(fruit, color: color(0.73, 0.28, 0.40),
                                               at: SCNVector3(Float(berry % 3 - 1) * 0.10, 0.25 + Float(berry % 2) * 0.09, 0.15)))
                    }
                }
            }
            for index in 0..<trees {
                let height = (index == 0 ? Float(1.25) : 1.0) + Float((seed / 5 + index) % 4) * 0.08
                let tree = model((seed + index) % 2 == 0 ? "tree_oak" : "tree_pineRoundA", height: height)
                tree.name = "forest-tree"
                let positions = [SCNVector3(0.24, 0, -0.24), SCNVector3(-0.27, 0, -0.20), SCNVector3(0.04, 0, 0.25)]
                tree.position = positions[index]
                tree.eulerAngles.y = CGFloat((seed + index * 3) % 8) * .pi / 4
                patch.addChildNode(tree)
            }
            if flowers >= 5 && !hasFox {
                let mushroom = model("mushroom_red", height: 0.23)
                mushroom.position = SCNVector3(-0.30, 0, 0.30)
                patch.addChildNode(mushroom)
            }
            if hasHive {
                let hive = beehive()
                hive.scale = SCNVector3(0.5, 0.5, 0.5)
                hive.position = SCNVector3(0.28, 0, 0.28)
                patch.addChildNode(hive)
                for index in 0..<1 {
                    let bee = bee()
                    bee.name = "forest-bee"
                    bee.scale = SCNVector3(0.5, 0.5, 0.5)
                    bee.position = SCNVector3(0.15, 0.65, 0.20)
                    patch.addChildNode(bee)
                    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        let orbit = SCNAction.customAction(duration: 5 + Double(index)) { node, elapsed in
                            let angle = Double(elapsed) / (5 + Double(index)) * .pi * 2
                            node.position = SCNVector3(cos(angle) * 0.35, 0.65 + sin(angle * 2) * 0.1, sin(angle) * 0.30)
                            node.eulerAngles.y = CGFloat(-angle)
                        }
                        bee.runAction(.repeatForever(orbit))
                    }
                }
            }
            if hasFox {
                let fox = fox()
                fox.name = "forest-fox"
                fox.scale = SCNVector3(0.5, 0.5, 0.5)
                fox.position = SCNVector3(-0.22, 0, 0.22)
                fox.eulerAngles.y = CGFloat(seed % 3) * 0.5
                patch.addChildNode(fox)
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    let stroll = SCNAction.customAction(duration: 12 + Double(seed % 4)) { node, elapsed in
                        let angle = Double(elapsed) / (12 + Double(seed % 4)) * .pi * 2
                        node.position = SCNVector3(cos(angle) * 0.36, 0.015 + abs(sin(angle * 12)) * 0.012, sin(angle) * 0.33)
                        node.eulerAngles.y = CGFloat(-angle)
                    }
                    fox.runAction(.repeatForever(.sequence([stroll, .wait(duration: 3)])))
                }
            }
          }
        }
        return scene
    }

    private static func place(_ node: SCNNode, index: Int, seed: Int, radius: Float) {
        let angle = Float(index) * 2.39996 + Float(seed) * 0.71
        let distance = radius * sqrt(Float((index * 7 + seed * 3) % 19 + 1) / 20)
        node.position.x = CGFloat(cos(angle) * distance)
        node.position.z = CGFloat(sin(angle) * distance * 0.8)
        node.eulerAngles.y = CGFloat(angle)
    }

    private static func beehive() -> SCNNode {
        let hive = SCNNode()
        for index in 0..<4 {
            let ring = SCNCylinder(radius: 0.19 - CGFloat(index) * 0.028, height: 0.09)
            ring.radialSegmentCount = 10
            hive.addChildNode(node(ring, color: color(0.84, 0.59 + CGFloat(index) * 0.03, 0.24),
                                   at: SCNVector3(0, 0.20 + Float(index) * 0.08, 0)))
        }
        hive.addChildNode(node(SCNBox(width: 0.46, height: 0.07, length: 0.42, chamferRadius: 0.02),
                               color: color(0.53, 0.34, 0.20), at: SCNVector3(0, 0.10, 0)))
        let hole = SCNSphere(radius: 0.06)
        hole.segmentCount = 8
        let entrance = node(hole, color: color(0.26, 0.19, 0.12), at: SCNVector3(0, 0.20, 0.18))
        entrance.scale.z = 0.25
        hive.addChildNode(entrance)
        return hive
    }

    private static func bee() -> SCNNode {
        let bee = SCNNode()
        let body = SCNSphere(radius: 0.08)
        body.segmentCount = 8
        let abdomen = node(body, color: color(0.98, 0.75, 0.25))
        abdomen.scale.z = 1.5
        bee.addChildNode(abdomen)
        let stripe = SCNCylinder(radius: 0.082, height: 0.045)
        stripe.radialSegmentCount = 8
        let band = node(stripe, color: color(0.28, 0.23, 0.17))
        band.eulerAngles.x = .pi / 2
        bee.addChildNode(band)
        for side: Float in [-1, 1] {
            let wing = SCNSphere(radius: 0.075)
            wing.segmentCount = 8
            let node = node(wing, color: color(0.94, 0.97, 0.90), at: SCNVector3(side * 0.065, 0.065, 0))
            node.scale = SCNVector3(0.7, 0.20, 1.2)
            bee.addChildNode(node)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let flutter = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(side) * 0.7, duration: 0.07)
                node.runAction(.repeatForever(.sequence([flutter, flutter.reversed()])))
            }
        }
        return bee
    }

    private static func fox() -> SCNNode {
        let fox = SCNNode()
        let orange = color(0.86, 0.43, 0.23)
        let cream = color(0.98, 0.90, 0.71)
        let body = SCNSphere(radius: 0.19)
        body.segmentCount = 8
        let torso = node(body, color: orange, at: SCNVector3(0, 0.21, 0))
        torso.scale = SCNVector3(0.8, 0.85, 1.5)
        fox.addChildNode(torso)
        let head = SCNSphere(radius: 0.16)
        head.segmentCount = 6
        fox.addChildNode(node(head, color: orange, at: SCNVector3(0, 0.35, 0.25)))
        let muzzle = SCNCone(topRadius: 0.025, bottomRadius: 0.10, height: 0.18)
        muzzle.radialSegmentCount = 5
        let snout = node(muzzle, color: cream, at: SCNVector3(0, 0.32, 0.40))
        snout.eulerAngles.x = .pi / 2
        fox.addChildNode(snout)
        for side: Float in [-1, 1] {
            let ear = SCNCone(topRadius: 0, bottomRadius: 0.075, height: 0.16)
            ear.radialSegmentCount = 3
            fox.addChildNode(node(ear, color: orange, at: SCNVector3(side * 0.105, 0.51, 0.23)))
            for z: Float in [-0.12, 0.16] {
                fox.addChildNode(node(SCNBox(width: 0.06, height: 0.15, length: 0.06, chamferRadius: 0),
                                     color: color(0.29, 0.23, 0.20), at: SCNVector3(side * 0.11, 0.08, z)))
            }
            let eye = SCNSphere(radius: 0.019)
            eye.segmentCount = 6
            fox.addChildNode(node(eye, color: color(0.15, 0.15, 0.13), at: SCNVector3(side * 0.09, 0.38, 0.36)))
        }
        let tail = SCNCone(topRadius: 0.045, bottomRadius: 0.12, height: 0.42)
        tail.radialSegmentCount = 6
        let brush = node(tail, color: orange, at: SCNVector3(0.09, 0.25, -0.34))
        brush.eulerAngles.x = -.pi / 3
        fox.addChildNode(brush)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let swish = SCNAction.rotateBy(x: 0, y: 0.22, z: 0, duration: 1.2)
            brush.runAction(.repeatForever(.sequence([swish, swish.reversed()])))
        }
        let tip = SCNSphere(radius: 0.07)
        tip.segmentCount = 6
        fox.addChildNode(node(tip, color: cream, at: SCNVector3(0.09, 0.36, -0.51)))
        return fox
    }
}
