import AppKit
import LofiMenCore
import SceneKit

extension GardenBuilder {
    /// One continuous island with footpaths between weeks, rather than floating heat-map tiles.
    static func addTerrain(to root: SCNNode, weeks: [GardenWeek], theme: RoomTheme) {
        let length = Double(weeks.count) * 1.06 + 0.18
        let outline = NSBezierPath()
        for side in [1.0, -1.0] {
            for index in 0...32 {
                let x = side * (Double(index) / 32 * 7.36 - 3.68)
                let edge = length / 2 + sin(x * 4.5) * 0.035 + cos(x * 9) * 0.02
                let point = NSPoint(x: x, y: -side * edge)
                if outline.isEmpty { outline.move(to: point) } else { outline.line(to: point) }
            }
            for index in 0...10 {
                let y = side * (Double(index) / 10 * (length - 0.24) - length / 2 + 0.12)
                outline.line(to: NSPoint(x: side * (3.82 + sin(y * 8) * 0.025), y: y))
            }
        }
        outline.close()
        let soil = flatShape(outline, depth: 0.22, color: hex(theme.garden.soil), y: -0.23)
        soil.name = "forest-ground"
        root.addChildNode(soil)
        root.addChildNode(flatShape(outline, depth: 0.025, color: hex(theme.garden.clearing), y: -0.03))

        let centerRow = Double(weeks.count - 1) / 2
        for row in 0..<max(0, weeks.count - 1) {
            let z = (Double(row) - centerRow + 0.5) * 1.06
            let path = NSBezierPath()
            for side in [1.0, -1.0] {
                let indices = side > 0 ? Array(0...64) : Array((0...64).reversed())
                for index in indices {
                    let x = Double(index) / 64 * 7.48 - 3.74
                    let point = NSPoint(x: x, y: -(z + sin(x * 2.5 + Double(row)) * 0.035 + side * 0.032))
                    if path.isEmpty { path.move(to: point) } else { path.line(to: point) }
                }
            }
            path.close()
            root.addChildNode(flatShape(path, color: hex(theme.garden.path), y: 0.004))
        }

        for (index, symbol) in Calendar.current.shortWeekdaySymbols.enumerated() {
            root.addChildNode(groundText(symbol.uppercased(), size: 0.12, color: NSColor(theme.secondary),
                                         at: SCNVector3(Double(index - 3) * 1.06, 0, -length / 2 - 0.22)))
        }
        for week in weeks {
            let caption = week.days[0].date.formatted(.dateTime.month(.abbreviated).day())
            root.addChildNode(groundText(caption, size: 0.11, color: NSColor(theme.muted),
                                         at: SCNVector3(-4.03, 0, (Double(week.index) - centerRow) * 1.06)))
        }
    }

    static func addClearing(to patch: SCNNode, day: ActivityDay, theme: RoomTheme) {
        // Irregular, overlapping ground cover gives each habitat its own footprint.
        if day.isInRange, day.duration > 0 {
            for layer in 0..<3 {
                let path = NSBezierPath()
                for index in 0..<14 {
                    let angle = Double(index) / 14 * .pi * 2
                    let radius = (0.36 + day.plantingRandom(index + layer * 20, lane: 7) * 0.17) * (1 - Double(layer) * 0.16)
                    let point = NSPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                    if index == 0 { path.move(to: point) } else { path.line(to: point) }
                }
                path.close()
                let lushness = min(1, day.duration / 10_800)
                let ground = hex(theme.garden.clearing).blended(
                    withFraction: 0.25 + lushness * 0.28 + Double(layer) * 0.08, of: hex(theme.garden.grass))!
                patch.addChildNode(flatShape(path, color: ground, y: 0.006 + Double(layer) * 0.002))
            }
        }
        for name in ["selection", "hover"] {
            let ring = SCNTorus(ringRadius: 0.47, pipeRadius: name == "selection" ? 0.012 : 0.007)
            ring.ringSegmentCount = 48
            ring.pipeSegmentCount = 5
            let outline = node(ring, color: NSColor(theme.accent), at: SCNVector3(0, 0.018, 0))
            outline.scale.z = 0.9
            outline.opacity = name == "selection" ? 0.95 : 0.45
            outline.name = "\(name)-\(day.date.timeIntervalSince1970)"
            outline.isHidden = true
            patch.addChildNode(outline)
        }
        let today = Calendar.current.isDateInToday(day.date)
        let marker = SCNCylinder(radius: 0.105, height: 0.012)
        marker.radialSegmentCount = 24
        let badge = node(marker, color: today ? NSColor(theme.accent) : hex(theme.garden.soil), at: SCNVector3(0, 0.015, 0.41))
        badge.opacity = day.isInRange ? 0.95 : 0.35
        badge.renderingOrder = 90
        badge.geometry?.firstMaterial?.readsFromDepthBuffer = false
        badge.geometry?.firstMaterial?.writesToDepthBuffer = false
        patch.addChildNode(badge)
        let text = groundText("\(Calendar.current.component(.day, from: day.date))", size: 0.115,
                              color: today ? NSColor(theme.background) : NSColor(theme.text), at: SCNVector3(0, 0.027, 0.41))
        text.opacity = day.isInRange ? 1 : 0.35
        patch.addChildNode(text)
    }

    static func birch(height: Double, foliage: NSColor, variation: Double) -> SCNNode {
        let tree = SCNNode()
        let trunk = SCNCylinder(radius: 0.025, height: height * 0.77)
        trunk.radialSegmentCount = 7
        tree.addChildNode(node(trunk, color: hex(0xD7D6BC), at: SCNVector3(0, height * 0.385, 0)))
        for index in 1...4 {
            let scar = SCNBox(width: 0.034, height: 0.014, length: 0.006, chamferRadius: 0)
            tree.addChildNode(node(scar, color: hex(0x696E5B), at: SCNVector3(0.002, height * Double(index) * 0.13, 0.024)))
        }
        for index in 0..<3 {
            let crown = SCNSphere(radius: height * (0.22 - Double(index) * 0.025))
            crown.segmentCount = 7
            let leaves = node(crown, color: foliage, at: SCNVector3(
                sin(Double(index) * 2.4 + variation * 3) * height * 0.07, height * (0.60 + Double(index) * 0.12), 0))
            leaves.scale = SCNVector3(0.86, 1.15, 0.82)
            tree.addChildNode(leaves)
        }
        return tree
    }

    private static func flatShape(_ path: NSBezierPath, depth: Double = 0, color: NSColor, y: Double) -> SCNNode {
        let shape = SCNShape(path: path, extrusionDepth: depth)
        shape.chamferRadius = 0
        let surface = node(shape, color: color, at: SCNVector3(0, y, 0))
        surface.eulerAngles.x = -.pi / 2
        return surface
    }

    private static func groundText(_ text: String, size: Double, color: NSColor, at position: SCNVector3) -> SCNNode {
        let geometry = SCNText(string: text, extrusionDepth: 0)
        geometry.font = .systemFont(ofSize: size, weight: .medium)
        geometry.flatness = 0.1
        let label = node(geometry, color: color, at: position)
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.readsFromDepthBuffer = false
        geometry.firstMaterial?.writesToDepthBuffer = false
        label.renderingOrder = 100
        let bounds = label.boundingBox
        label.pivot = SCNMatrix4MakeTranslation((bounds.max.x + bounds.min.x) / 2, (bounds.max.y + bounds.min.y) / 2, 0)
        label.eulerAngles.x = -.pi / 2
        return label
    }
}
