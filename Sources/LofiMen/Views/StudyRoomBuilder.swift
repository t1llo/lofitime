import AppKit
import LofiMenCore
import SceneKit
import SwiftUI

/// KayKit furniture with a custom room shell, computer, growing foliage and animated details.
@MainActor final class StudyRoomBuilder {
    let scene = SCNScene()
    private let growth: FocusRoom
    private let theme: RoomTheme
    private let wood = color(0xB98561)
    private let darkWood = color(0x725444)
    private let cream = color(0xF3DFC0)
    private let pink = color(0xD99B98)
    private let fabric: NSColor
    private let leaf: NSColor
    private let wall: NSColor
    private var root: SCNNode { scene.rootNode }

    static func scene(growth: FocusRoom, theme: RoomTheme) -> SCNScene {
        StudyRoomBuilder(growth: growth, theme: theme).scene
    }

    private init(growth: FocusRoom, theme: RoomTheme) {
        self.growth = growth
        self.theme = theme
        fabric = NSColor(theme.accent).blended(withFraction: 0.2, of: Self.color(0xB5A294))!
        leaf = NSColor(theme.activity).blended(withFraction: 0.45, of: Self.color(0x497E5D))!
        wall = NSColor(theme.accent).blended(withFraction: 0.78, of: Self.color(0xD8C7B0))!
        scene.background.contents = NSColor(theme.surface)
        lighting()
        shell()
        window()
        desk()
        bed()
        if growth.minutes > 0 {
            plant(at: SCNVector3(-1.25, 1.39, -1.10), size: 0.54, flowering: false, name: "desk-plant")
            mug(at: SCNVector3(-2.00, 1.39, -0.70))
        }
        if growth.minutes >= 15 {
            plant(at: SCNVector3(-3.32, 0.06, 0.86), size: 1.45, flowering: false, name: "floor-plant")
        }
        if growth.minutes >= 45 {
            lamp(at: SCNVector3(-3.35, 1.39, -1.35), floor: false)
            studyDetails()
        }
        if growth.minutes >= 90 { rug() }
        if growth.minutes >= 180 { bookshelf(); readingNook() }
        if growth.minutes >= 300 {
            lamp(at: SCNVector3(1.14, 0.04, 0.72), floor: true)
            wallArt()
            bedsideDetails()
            plant(at: SCNVector3(3.50, 0.05, 1.16), size: 0.85, flowering: true, name: "flower-pot")
        }
        if growth.minutes >= 420 { hangingPlant(); keepsakeShelf() }
        if growth.minutes >= 540 { sleepingCat() }
        if growth.minutes >= 720 { fairyLights() }
    }

    private func lighting() {
        let camera = SCNNode()
        camera.name = "camera"
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.projectionDirection = .vertical
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 50
        camera.camera?.wantsHDR = true
        camera.camera?.bloomIntensity = 0.35
        camera.camera?.bloomThreshold = 1.1
        camera.position = SCNVector3(5.4, 4.4, 12)
        camera.look(at: SCNVector3(0, 1.85, 0))
        root.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = Self.color(0xF6E9DA)
        ambient.light?.intensity = 380
        root.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = Self.color(0xFFE5C0)
        sun.light?.intensity = 740
        sun.light?.castsShadow = true
        sun.light?.shadowRadius = 5
        sun.light?.shadowSampleCount = 8
        sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.light?.shadowColor = NSColor(calibratedRed: 0.22, green: 0.16, blue: 0.20, alpha: 0.35)
        sun.eulerAngles = SCNVector3(-0.7, -0.5, -0.3)
        root.addChildNode(sun)
    }

    private func shell() {
        box(root, (8.5, 0.26, 4.5), at: SCNVector3(0, -0.14, 0), color: darkWood, radius: 0.10, name: "room-floor")
        for index in 0..<16 {
            let tint = wood.blended(withFraction: CGFloat(index % 3) * 0.045, of: cream)!
            box(root, (0.51, 0.035, 4.35), at: SCNVector3(-3.99 + Double(index) * 0.53, 0.01, 0), color: tint, radius: 0.012)
            for z in [-1.35, 0.75] {
                box(root, (0.49, 0.003, 0.014), at: SCNVector3(-3.99 + Double(index) * 0.53, 0.03, z + Double(index % 2) * 0.35), color: darkWood.withAlphaComponent(0.35), radius: 0)
            }
        }
        box(root, (8.5, 4.15, 0.16), at: SCNVector3(0, 2.03, -2.20), color: wall, name: "back-wall")
        box(root, (0.16, 4.15, 4.45), at: SCNVector3(-4.22, 2.03, 0), color: wall, name: "side-wall")
        box(root, (8.35, 0.16, 0.07), at: SCNVector3(0, 0.12, -2.08), color: cream)
        box(root, (0.07, 0.16, 4.25), at: SCNVector3(-4.10, 0.12, 0), color: cream)
        box(root, (8.55, 0.12, 0.22), at: SCNVector3(0, 4.10, -2.2), color: wood)
        box(root, (0.22, 0.12, 4.5), at: SCNVector3(-4.22, 4.10, 0), color: wood)
    }

    private func window() {
        let frame = group("window", at: SCNVector3(-2.22, 2.73, -2.03))
        box(frame, (2.87, 2.08, 0.12), at: SCNVector3Zero, color: darkWood, radius: 0.09)
        let sky = box(frame, (2.64, 1.85, 0.03), at: SCNVector3(0, 0, 0.075), color: Self.color(0x56677F))
        sky.geometry?.firstMaterial?.lightingModel = .constant
        let moon = orb(frame, size: SCNVector3(0.19, 0.19, 0.035), at: SCNVector3(0.80, 0.56, 0.11), color: cream)
        moon.geometry?.firstMaterial?.emission.contents = cream
        for i in 0..<15 {
            let star = orb(frame, size: SCNVector3(0.012, 0.018, 0.007),
                           at: SCNVector3(-1.15 + Double((i * 11) % 23) * 0.1, -0.2 + Double((i * 7) % 11) * 0.1, 0.11), color: cream)
            star.geometry?.firstMaterial?.emission.contents = cream
        }
        for i in 0..<8 {
            let height = 0.20 + Double((i * 7) % 5) * 0.075
            box(frame, (0.36, height, 0.025), at: SCNVector3(-1.12 + Double(i) * 0.32, -0.89 + height / 2, 0.11), color: Self.color(i % 2 == 0 ? 0x596878 : 0x66768B), radius: 0.008)
            for row in 0..<2 {
                box(frame, (0.042, 0.046, 0.01), at: SCNVector3(-1.08 + Double(i) * 0.32, -0.80 + Double(row) * 0.10, 0.13), color: cream, radius: 0.004)
            }
        }
        for x in [-1.34, 0, 1.34] {
            box(frame, (0.075, 1.98, 0.16), at: SCNVector3(x, 0, 0.18), color: cream, radius: 0.015)
        }
        for y in [-0.95, 0, 0.95] {
            box(frame, (2.75, 0.075, 0.16), at: SCNVector3(0, y, 0.18), color: cream, radius: 0.015)
        }
        box(frame, (3.05, 0.12, 0.45), at: SCNVector3(0, -1.04, 0.18), color: wood)
        if growth.minutes >= 90 {
            for side in [-1.0, 1.0] {
                for fold in 0..<4 {
                    let curtain = box(frame, (0.13, 1.96, 0.13), at: SCNVector3(side * (1.14 + Double(fold) * 0.12), 0.01, 0.26), color: fabric, radius: 0.055)
                    curtain.eulerAngles.z = side * -0.022
                }
                box(frame, (0.48, 0.065, 0.17), at: SCNVector3(side * 1.34, -0.3, 0.30), color: cream)
            }
            rod(frame, from: SCNVector3(-1.75, 1.07, 0.28), to: SCNVector3(1.75, 1.07, 0.28), radius: 0.035, color: darkWood)
        }
    }

    private func desk() {
        furniture(.desk, name: "desk", size: SCNVector3(2.92, 1.34, 1.36), at: SCNVector3(-2.28, 0.04, -1.04))
        let computer = group("computer", at: SCNVector3(-2.53, 1.39, -1.34))
        box(computer, (0.49, 0.05, 0.34), at: SCNVector3(0, 0.02, 0), color: cream)
        box(computer, (0.10, 0.24, 0.10), at: SCNVector3(0, 0.15, -0.05), color: cream)
        box(computer, (0.97, 0.64, 0.15), at: SCNVector3(0, 0.54, -0.04), color: cream, radius: 0.075)
        let screen = box(computer, (0.84, 0.49, 0.012), at: SCNVector3(0, 0.56, 0.042), color: Self.color(0x526E77), name: "desktop-screen")
        screen.geometry?.firstMaterial?.emission.contents = Self.color(0x29484C)
        for index in 0..<4 {
            box(computer, (0.40 - Double(index % 3) * 0.06, 0.022, 0.01), at: SCNVector3(-0.08, 0.68 - Double(index) * 0.075, 0.054), color: Self.color(0xB6D0BF), radius: 0.006)
        }
        box(computer, (0.72, 0.035, 0.25), at: SCNVector3(0, 0.02, 0.45), color: cream, radius: 0.025)
        for row in 0..<3 {
            for key in 0..<9 {
                box(computer, (0.05, 0.008, 0.035), at: SCNVector3(-0.28 + Double(key) * 0.07, 0.042, 0.38 + Double(row) * 0.06), color: wood, radius: 0.006)
            }
        }
        orb(computer, size: SCNVector3(0.06, 0.025, 0.085), at: SCNVector3(0.56, 0.035, 0.43), color: cream)
        furniture(.chair, name: "chair", size: SCNVector3(0.84, 1.40, 0.90), at: SCNVector3(-2.22, 0.04, 0.38), yaw: .pi)
    }

    private func bed() {
        furniture(.bed, name: "bed", size: SCNVector3(2.32, 1.22, 2.65), at: SCNVector3(2.50, 0.04, -0.65))
        if growth.minutes >= 300 {
            furniture(.pillow, name: "cozy-pillow", size: SCNVector3(0.55, 0.17, 0.43), at: SCNVector3(3.04, 0.93, -1.16), yaw: 0.25)
            furniture(.cushion, name: "cozy-cushion", size: SCNVector3(0.50, 0.17, 0.41), at: SCNVector3(1.97, 0.93, -1.20), yaw: -0.18)
        }
    }

    private func rug() {
        furniture(.rug, name: "rug", size: SCNVector3(3.28, 0.045, 2.16), at: SCNVector3(-0.2, 0.04, 0.60))
    }

    private func bookshelf() {
        let shelf = group("bookshelf", at: SCNVector3(0.37, 0, -1.88))
        for row in 0..<4 {
            let model = RoomFurniture.node(.shelf, size: SCNVector3(1.40, 0.28, 0.46), theme: theme)
            model.position.y = 0.25 + Double(row) * 0.66
            shelf.addChildNode(model)
        }
        for index in 0..<growth.bookCount {
            let row = index / 6
            let height = 0.37 + Double((index * 7) % 4) * 0.038
            let x = -0.54 + Double(index % 6) * 0.20
            let book = RoomFurniture.node(.book, size: SCNVector3(0.14, height, 0.29), theme: theme)
            book.name = "book-\(index)"
            book.eulerAngles.y = .pi
            book.position = SCNVector3(x, 0.53 + Double(row) * 0.66, 0.015)
            shelf.addChildNode(book)
        }
        furniture(.ledge, name: "plant-shelf", size: SCNVector3(0.55, 0.15, 0.38), at: SCNVector3(0.57, 3.13, -1.90))
        furniture(.cactus, name: "shelf-cactus", size: SCNVector3(0.34, 0.38, 0.34), at: SCNVector3(0.57, 3.18, -1.87))
    }

    private func lamp(at position: SCNVector3, floor: Bool) {
        let height = floor ? 2.18 : 0.61
        let width = floor ? 0.80 : 0.58
        let lamp = furniture(floor ? .floorLamp : .tableLamp, name: floor ? "floor-lamp" : "desk-lamp",
                             size: SCNVector3(width, height, width), at: position)
        let bulb = orb(lamp, size: SCNVector3(0.09, 0.045, 0.09), at: SCNVector3(0, height * 0.72, 0), color: cream)
        bulb.geometry?.firstMaterial?.emission.contents = Self.color(0xFFD68D)
        let light = SCNLight()
        light.type = .omni
        light.color = Self.color(0xFFCB80)
        light.intensity = floor ? 12 : 6
        light.attenuationStartDistance = 0.15
        light.attenuationEndDistance = floor ? 3 : 1.7
        bulb.light = light
    }

    private func wallArt() {
        let art = furniture(.frame, name: "wall-art", size: SCNVector3(1.52, 0.96, 0.12), at: SCNVector3(2.52, 2.50, -2.04))
        orb(art, size: SCNVector3(0.19, 0.19, 0.018), at: SCNVector3(0.24, 0.62, 0.069), color: pink)
        for index in 0..<3 {
            let hill = orb(art, size: SCNVector3(0.27, 0.15, 0.015), at: SCNVector3(-0.30 + Double(index) * 0.29, 0.28 + Double(index % 2) * 0.08, 0.08), color: index == 1 ? leaf : fabric)
            hill.eulerAngles.z = Double(index - 1) * 0.25
        }
    }

    private func mug(at position: SCNVector3) {
        let mug = group("tea", at: position)
        cylinder(mug, radius: 0.085, height: 0.16, at: SCNVector3(0, 0.08, 0), color: pink)
        cylinder(mug, radius: 0.071, height: 0.005, at: SCNVector3(0, 0.162, 0), color: darkWood)
        let handle = SCNTorus(ringRadius: 0.060, pipeRadius: 0.017)
        handle.ringSegmentCount = 20
        let ring = node(handle, color: pink, at: SCNVector3(0.085, 0.09, 0))
        ring.eulerAngles.x = .pi / 2
        mug.addChildNode(ring)
        for index in 0..<3 {
            let steam = orb(mug, size: SCNVector3(0.023, 0.05, 0.023),
                            at: SCNVector3(Double(index - 1) * 0.035, 0.24 + Double(index) * 0.045, 0), color: cream.withAlphaComponent(0.2))
            let rise = SCNAction.group([.moveBy(x: 0.035, y: 0.14, z: 0, duration: 2.5), .fadeOut(duration: 2.5)])
            steam.runAction(.repeatForever(.sequence([rise, .moveBy(x: -0.035, y: -0.14, z: 0, duration: 0), .fadeIn(duration: 0.2)])))
        }
    }

    private func studyDetails() {
        let notebook = group("open-notebook", at: SCNVector3(-1.56, 1.40, -0.77))
        notebook.eulerAngles.y = -0.18
        box(notebook, (0.51, 0.035, 0.33), at: SCNVector3Zero, color: leaf, radius: 0.02)
        for side in [-1.0, 1.0] {
            box(notebook, (0.235, 0.025, 0.30), at: SCNVector3(side * 0.125, 0.028, 0), color: cream, radius: 0.01)
            for row in 0..<5 {
                box(notebook, (0.17, 0.002, 0.005), at: SCNVector3(side * 0.125, 0.042, -0.1 + Double(row) * 0.04), color: wood, radius: 0)
            }
        }
        rod(notebook, from: SCNVector3(0.1, 0.052, -0.12), to: SCNVector3(0.18, 0.052, 0.09), radius: 0.012, color: pink)
        let board = group("pinboard", at: SCNVector3(-4.08, 2.58, 0.51))
        board.eulerAngles.y = .pi / 2
        box(board, (1.37, 1.15, 0.07), at: SCNVector3Zero, color: wood)
        box(board, (1.23, 1.01, 0.022), at: SCNVector3(0, 0, 0.05), color: Self.color(0xB68D6A))
        for i in 0..<4 {
            let note = box(board, (0.38, 0.35, 0.009), at: SCNVector3(i % 2 == 0 ? -0.28 : 0.28, i < 2 ? 0.23 : -0.23, 0.07), color: i == 2 ? pink : cream, radius: 0.003)
            note.eulerAngles.z = Double(i - 2) * 0.065
            orb(note, size: SCNVector3(0.022, 0.022, 0.013), at: SCNVector3(0, 0.135, 0.02), color: leaf)
            for row in 0..<3 {
                box(note, (0.21, 0.012, 0.003), at: SCNVector3(0, 0.05 - Double(row) * 0.06, 0.007), color: wood, radius: 0.002)
            }
        }
    }

    private func readingNook() {
        furniture(.armchair, name: "reading-chair", size: SCNVector3(1.23, 0.91, 1.09), at: SCNVector3(-0.30, 0.085, 0.92), yaw: -0.22)
        furniture(.cushion, name: "floor-cushion", size: SCNVector3(0.55, 0.17, 0.43), at: SCNVector3(0.69, 0.085, 1.41), yaw: 0.3)
    }

    private func bedsideDetails() {
        furniture(.cabinet, name: "bedside-table", size: SCNVector3(0.53, 0.69, 0.58), at: SCNVector3(3.91, 0.04, -1.57))
        furniture(.books, name: "bedside-books", size: SCNVector3(0.33, 0.24, 0.18), at: SCNVector3(3.91, 0.73, -1.71))
        let candle = group("bedside-candle", at: SCNVector3(3.91, 0.73, -1.42))
        cylinder(candle, radius: 0.092, height: 0.15, at: SCNVector3(0, 0.075, 0), color: cream)
        let flame = orb(candle, size: SCNVector3(0.025, 0.06, 0.025), at: SCNVector3(0, 0.2, 0), color: cream)
        flame.geometry?.firstMaterial?.emission.contents = Self.color(0xFFC16A)
        flame.geometry?.firstMaterial?.emission.intensity = 1.5
        let glow = SCNLight()
        glow.type = .omni
        glow.color = Self.color(0xFFBF77)
        glow.intensity = 3
        glow.attenuationStartDistance = 0.1
        glow.attenuationEndDistance = 1
        flame.light = glow
        for side in [-1.0, 1.0] {
            let slipper = orb(root, size: SCNVector3(0.11, 0.08, 0.22), at: SCNVector3(3.63 + side * 0.14, 0.10, 0.57), color: pink)
            slipper.eulerAngles.y = side * 0.12
            orb(slipper, size: SCNVector3(0.68, 0.3, 0.41), at: SCNVector3(0, 0.85, -0.1), color: cream)
        }
    }

    private func keepsakeShelf() {
        let shelf = furniture(.ledge, name: "keepsake-shelf", size: SCNVector3(1.94, 0.25, 0.32), at: SCNVector3(2.54, 1.88, -1.94))
        furniture(.photo, name: "keepsake-photo", size: SCNVector3(0.30, 0.37, 0.23), at: SCNVector3(2.00, 1.97, -1.89))
        plant(at: SCNVector3(3.19, 1.97, -1.91), size: 0.43, flowering: true, name: "bedside-flowers")
        let bunny = SCNNode()
        bunny.position = SCNVector3(0.02, 0.20, 0.06)
        shelf.addChildNode(bunny)
        orb(bunny, size: SCNVector3(0.115, 0.12, 0.095), at: SCNVector3Zero, color: cream)
        for side in [-1.0, 1.0] {
            orb(bunny, size: SCNVector3(0.033, 0.1, 0.035), at: SCNVector3(side * 0.05, 0.17, 0), color: cream)
            orb(bunny, size: SCNVector3(0.012, 0.016, 0.008), at: SCNVector3(side * 0.04, 0.02, 0.091), color: darkWood)
        }
    }

    private func plant(at position: SCNVector3, size: Double, flowering: Bool, name: String) {
        let plant = group(name, at: position)
        let potHeight = size * 0.26
        let pot = SCNCone(topRadius: size * 0.19, bottomRadius: size * 0.14, height: potHeight)
        pot.radialSegmentCount = 28
        plant.addChildNode(node(pot, color: flowering ? pink : cream, at: SCNVector3(0, potHeight / 2, 0)))
        cylinder(plant, radius: size * 0.19, height: size * 0.038, at: SCNVector3(0, potHeight, 0), color: flowering ? pink : cream)
        cylinder(plant, radius: size * 0.166, height: 0.012, at: SCNVector3(0, potHeight + 0.007, 0), color: darkWood)
        let stems = SCNNode()
        stems.position.y = potHeight
        plant.addChildNode(stems)
        let fullness = growth.plantGrowth
        let count = 3 + Int(fullness * 6)
        let height = size * (0.20 + fullness * 0.66)
        for index in 0..<count {
            let angle = Double(index) * 2.39996
            let spread = size * (0.12 + fullness * 0.18)
            let tip = SCNVector3(cos(angle) * spread, height * (0.5 + Double(index % 3) * 0.2), sin(angle) * spread)
            rod(stems, from: SCNVector3Zero, to: tip, radius: size * 0.014, color: leaf)
            let foliage = orb(stems, size: SCNVector3(size * 0.115, size * 0.22, size * 0.046), at: tip, color: index % 2 == 0 ? leaf : leaf.blended(withFraction: 0.23, of: cream)!)
            foliage.eulerAngles = SCNVector3(0.35, angle, cos(angle) * 0.65)
            if flowering, index.isMultiple(of: 2) {
                flower(on: stems, at: SCNVector3(tip.x, tip.y + size * 0.13, tip.z), size: size * (0.065 + fullness * 0.08), variation: index)
            }
        }
        let sway = SCNAction.rotateBy(x: 0, y: 0, z: 0.018, duration: 2.8)
        stems.runAction(.repeatForever(.sequence([sway, sway.reversed()])))
    }

    private func flower(on parent: SCNNode, at position: SCNVector3, size: Double, variation: Int) {
        let bloom = SCNNode()
        bloom.position = position
        bloom.name = "blossom"
        parent.addChildNode(bloom)
        for index in 0..<6 {
            let angle = Double(index) / 6 * .pi * 2
            let petal = orb(bloom, size: SCNVector3(size * 0.43, size * 0.67, size * 0.28), at: SCNVector3(cos(angle) * size * 0.58, sin(angle) * size * 0.58, 0), color: variation % 4 == 0 ? pink : cream)
            petal.eulerAngles.z = angle - .pi / 2
        }
        orb(bloom, size: SCNVector3(size * 0.31, size * 0.31, size * 0.29), at: SCNVector3(0, 0, size * 0.16), color: Self.color(0xE6B868))
    }

    private func hangingPlant() {
        let position = SCNVector3(-0.70, 2.85, -1.80)
        plant(at: position, size: 0.53, flowering: false, name: "hanging-plants")
        for side in [-1.0, 1.0] {
            rod(root, from: SCNVector3(position.x + side * 0.12, position.y + 0.04, position.z), to: SCNVector3(position.x, 3.94, position.z), radius: 0.012, color: cream)
            let count = 7 + Int(growth.plantGrowth * 6)
            for index in 0..<count {
                let x = position.x + side * (0.12 + sin(Double(index) * 0.75) * 0.065)
                let y = position.y + 0.12 - Double(index) * 0.069
                let vine = orb(root, size: SCNVector3(0.066, 0.083, 0.023), at: SCNVector3(x, y, position.z + 0.17), color: leaf)
                vine.eulerAngles.z = side * 0.6
            }
        }
    }

    private func sleepingCat() {
        let cat = group("sleeping-cat", at: SCNVector3(2.43, 0.96, 0.05))
        let fur = Self.color(0xD4AD7E)
        orb(cat, size: SCNVector3(0.37, 0.20, 0.26), at: SCNVector3Zero, color: fur)
        orb(cat, size: SCNVector3(0.19, 0.18, 0.16), at: SCNVector3(-0.24, 0.10, 0.13), color: fur)
        for side in [-1.0, 1.0] {
            let ear = SCNCone(topRadius: 0.008, bottomRadius: 0.079, height: 0.16)
            ear.radialSegmentCount = 3
            cat.addChildNode(node(ear, color: fur, at: SCNVector3(-0.24 + side * 0.105, 0.29, 0.13)))
            rod(cat, from: SCNVector3(-0.24 + side * 0.060 - 0.025, 0.11, 0.283), to: SCNVector3(-0.24 + side * 0.060 + 0.025, 0.10, 0.283), radius: 0.010, color: darkWood)
        }
        orb(cat, size: SCNVector3(0.020, 0.015, 0.010), at: SCNVector3(-0.24, 0.055, 0.29), color: pink)
        let tail = SCNTorus(ringRadius: 0.23, pipeRadius: 0.065)
        let curled = node(tail, color: fur, at: SCNVector3(0.08, -0.07, 0.02))
        curled.scale = SCNVector3(1.2, 0.65, 1)
        cat.addChildNode(curled)
    }

    private func fairyLights() {
        let lights = group("fairy-lights", at: SCNVector3Zero)
        var previous: SCNVector3?
        for index in 0...24 {
            let x = -3.95 + Double(index) * 7.85 / 24
            let y = 3.94 - sin(Double(index) / 24 * .pi) * 0.30
            let point = SCNVector3(x, y, -1.94)
            if let previous { rod(lights, from: previous, to: point, radius: 0.011, color: darkWood) }
            if index.isMultiple(of: 2) {
                let bulb = orb(lights, size: SCNVector3(0.045, 0.065, 0.045), at: SCNVector3(x, y - 0.075, -1.94), color: cream)
                bulb.geometry?.firstMaterial?.emission.contents = Self.color(0xFFD591)
                bulb.geometry?.firstMaterial?.emission.intensity = 1.4
            }
            previous = point
        }
    }

    private static func color(_ value: UInt32) -> NSColor { NSColor(Color(hex: value)) }

    @discardableResult private func furniture(_ model: RoomFurniture.Model, name: String, size: SCNVector3,
                                             at position: SCNVector3, yaw: Double = 0) -> SCNNode {
        let group = group(name, at: position)
        group.eulerAngles.y = yaw
        group.addChildNode(RoomFurniture.node(model, size: size, theme: theme))
        return group
    }

    private func group(_ name: String, at position: SCNVector3) -> SCNNode {
        let group = SCNNode()
        group.name = name
        group.position = position
        root.addChildNode(group)
        return group
    }

    private func node(_ geometry: SCNGeometry, color: NSColor, at position: SCNVector3) -> SCNNode {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.roughness.contents = 0.95
        material.lightingModel = .physicallyBased
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = position
        return node
    }

    @discardableResult private func box(_ parent: SCNNode, _ size: (CGFloat, CGFloat, CGFloat), at position: SCNVector3,
                                       color: NSColor, radius: CGFloat = 0.035, name: String? = nil) -> SCNNode {
        let geometry = SCNBox(width: size.0, height: size.1, length: size.2, chamferRadius: min(radius, min(size.0, size.1, size.2) / 2))
        geometry.chamferSegmentCount = 4
        let box = node(geometry, color: color, at: position)
        box.name = name
        parent.addChildNode(box)
        return box
    }

    @discardableResult private func orb(_ parent: SCNNode, size: SCNVector3, at position: SCNVector3, color: NSColor) -> SCNNode {
        let geometry = SCNSphere(radius: 1)
        geometry.segmentCount = 20
        let orb = node(geometry, color: color, at: position)
        orb.scale = size
        parent.addChildNode(orb)
        return orb
    }

    private func cylinder(_ parent: SCNNode, radius: CGFloat, height: CGFloat, at position: SCNVector3, color: NSColor) {
        let geometry = SCNCylinder(radius: radius, height: height)
        geometry.radialSegmentCount = 28
        parent.addChildNode(node(geometry, color: color, at: position))
    }

    private func rod(_ parent: SCNNode, from start: SCNVector3, to end: SCNVector3, radius: CGFloat, color: NSColor) {
        let length = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2) + pow(end.z - start.z, 2))
        guard length > 0 else { return }
        let geometry = SCNCylinder(radius: radius, height: length)
        geometry.radialSegmentCount = 10
        let rod = node(geometry, color: color, at: SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2, (start.z + end.z) / 2))
        rod.look(at: end, up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 1, 0))
        parent.addChildNode(rod)
    }
}
