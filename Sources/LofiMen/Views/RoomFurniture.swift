import AppKit
import ModelIO
import SceneKit
import SceneKit.ModelIO
import SwiftUI

/// Bundled CC0 meshes from KayKit Furniture Bits. Originals and license live beside the texture.
@MainActor enum RoomFurniture {
    enum Model: String, CaseIterable {
        case desk = "table_medium_long", chair = "chair_B", bed = "bed_double_A"
        case armchair = "armchair_pillows", cabinet = "cabinet_small"
        case floorLamp = "lamp_standing", tableLamp = "lamp_table"
        case rug = "rug_rectangle_stripes_A", shelf = "shelf_A_big", ledge = "shelf_B_large"
        case book = "book_single", books = "book_set", cactus = "cactus_small_A"
        case frame = "pictureframe_large_B", photo = "pictureframe_standing_A"
        case pillow = "pillow_A", cushion = "pillow_B"
    }

    private static var meshes: [Model: SCNNode] = [:]
    private static var materials: [String: SCNMaterial] = [:]

    static func node(_ model: Model, size: SCNVector3, theme: RoomTheme) -> SCNNode {
        let source = mesh(model)
        let content = source.clone()
        // Clones share geometry by default. Give each instance its own material assignment.
        content.enumerateHierarchy { node, _ in
            if let geometry = node.geometry?.copy() as? SCNGeometry {
                geometry.materials = [material(theme)]
                node.geometry = geometry
            }
        }
        let bounds = content.boundingBox
        let extent = SCNVector3(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y, bounds.max.z - bounds.min.z)
        guard extent.x > 0, extent.y > 0, extent.z > 0 else {
            assertionFailure("Empty furniture mesh: \(model.rawValue)")
            return SCNNode()
        }
        content.position = SCNVector3(-(bounds.min.x + bounds.max.x) / 2, -bounds.min.y,
                                     -(bounds.min.z + bounds.max.z) / 2)
        let centered = SCNNode()
        centered.addChildNode(content)
        centered.scale = SCNVector3(size.x / extent.x, size.y / extent.y, size.z / extent.z)
        let result = SCNNode()
        result.name = "furniture-\(model.rawValue)"
        result.addChildNode(centered)
        return result
    }

    private static func mesh(_ model: Model) -> SCNNode {
        if let cached = meshes[model] { return cached }
        guard let url = AppResources.bundle.url(forResource: model.rawValue, withExtension: "obj", subdirectory: "RoomFurniture") else {
            assertionFailure("Missing furniture resource: \(model.rawValue)")
            return SCNNode()
        }
        let asset = MDLAsset(url: url)
        let scene = SCNScene(mdlAsset: asset)
        let mesh = scene.rootNode.clone()
        meshes[model] = mesh
        return mesh
    }

    private static func material(_ theme: RoomTheme) -> SCNMaterial {
        let key = NSColor(theme.accent).description
        if let cached = materials[key] { return cached }
        let material = SCNMaterial()
        material.name = "KayKit furniture palette"
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.85
        material.metalness.contents = 0
        if let url = AppResources.bundle.url(forResource: "furniturebits_texture", withExtension: "png", subdirectory: "RoomFurniture"),
           let image = NSImage(contentsOf: url), let palette = themedPalette(image, theme: theme) {
            material.diffuse.contents = palette
        } else {
            assertionFailure("Missing furniture palette")
            material.diffuse.contents = NSColor(theme.accent)
        }
        materials[key] = material
        return material
    }

    private static func themedPalette(_ image: NSImage, theme: RoomTheme) -> NSImage? {
        // The palette is gradients, so a small texture preserves the artwork. Only the blue
        // and yellow accent swatches are recolored; wood, paper, foliage and metal stay original.
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap),
              let accent = NSColor(theme.accent).usingColorSpace(.deviceRGB) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
        NSGraphicsContext.restoreGraphicsState()
        for y in 64..<128 {
            for x in 0..<128 {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let shade = 0.65 + 0.35 * max(color.redComponent, color.greenComponent, color.blueComponent)
                let tint = x < 64 ? accent.blended(withFraction: 0.18, of: .white)! : accent
                bitmap.setColor(NSColor(deviceRed: tint.redComponent * shade, green: tint.greenComponent * shade,
                                        blue: tint.blueComponent * shade, alpha: 1), atX: x, y: y)
            }
        }
        let result = NSImage(size: NSSize(width: 256, height: 256))
        result.addRepresentation(bitmap)
        return result
    }
}
