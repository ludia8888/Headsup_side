// Crop the shipped scene to an opaque 1024px app icon, preserving its aspect ratio.
// Usage: swift scripts/make-icon.swift <output.png> [portrait.png]
import AppKit

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift scripts/make-icon.swift <output.png> [portrait.png]\n", stderr)
    exit(1)
}
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : root.appendingPathComponent("ios/App/Assets.xcassets/CharacterScene.imageset/scene.png")
guard let image = NSImage(contentsOf: source),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fputs("Could not load the portrait.\n", stderr); exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.white.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
let cropSide = min(image.size.width, image.size.height)
let portraitCrop = NSRect(x: (image.size.width - cropSide) / 2,
                          y: image.size.height - cropSide, width: cropSide, height: cropSide)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
           from: portraitCrop, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
