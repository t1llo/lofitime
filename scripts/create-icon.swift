import AppKit

let source = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "assets/icon.png")
guard let image = NSImage(contentsOf: source) else { fatalError("Cannot load app icon: \(source.path)") }
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(pixels: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
