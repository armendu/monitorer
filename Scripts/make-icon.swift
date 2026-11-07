// Draws Monitorer's app icon into an .iconset that `iconutil` turns into Resources/AppIcon.icns.
// Run through `make icon`; the .icns is checked in, so a normal build doesn't need this.
//
// The shape follows the macOS icon grid: an 824-point rounded square on a 1024 canvas, so the
// system shows it as a regular app icon rather than placing it on a grey backing.

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // A soft drop shadow, as on Apple's own icons.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.orange.setFill()
    shape.fill()
    context.restoreGState()

    NSGradient(colors: [NSColor(red: 1.0, green: 0.84, blue: 0.25, alpha: 1),
                        NSColor(red: 0.98, green: 0.55, blue: 0.13, alpha: 1)])!
        .draw(in: shape, angle: -90)

    // A faint highlight along the top edge.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.35), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(roundedRect: body.insetBy(dx: 6, dy: 6), xRadius: 180, yRadius: 180), angle: -90)

    // Drawn unscaled at the final size: under the scaled context, AppKit rasterizes the symbol
    // at 1024-point size first and the small icons come out blurry.
    context.scaleBy(x: 1 / scale, y: 1 / scale)
    let configuration = NSImage.SymbolConfiguration(pointSize: 470 * scale, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let sun = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let size = sun.size
        let center = 512 * scale
        sun.draw(in: CGRect(x: center - size.width / 2, y: center - size.height / 2, width: size.width, height: size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: output.appendingPathComponent(name))
    }
}
