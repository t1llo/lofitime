import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 52, y: 52, width: 920, height: 920)
    let silhouette = NSBezierPath(roundedRect: rect, xRadius: 218, yRadius: 218)
    NSColor(calibratedRed: 0.102, green: 0.106, blue: 0.149, alpha: 1).setFill()
    silhouette.fill()
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.26, alpha: 1),
               ending: NSColor(calibratedRed: 0.102, green: 0.106, blue: 0.149, alpha: 1))!
        .draw(in: silhouette, angle: -60)
    NSColor(calibratedRed: 0.478, green: 0.635, blue: 0.969, alpha: 0.25).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 169, y: 169, width: 686, height: 686))
    ring.lineWidth = 4
    ring.stroke()
    let heights: [CGFloat] = [145, 270, 395, 245, 135]
    NSColor(calibratedRed: 0.478, green: 0.635, blue: 0.969, alpha: 1).setFill()
    for (index, height) in heights.enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 308 + CGFloat(index) * 88, y: 512 - height / 2,
                                         width: 56, height: height), xRadius: 28, yRadius: 28).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(pixels: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
