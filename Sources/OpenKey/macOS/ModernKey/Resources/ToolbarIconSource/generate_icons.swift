import AppKit
import Foundation

let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let icons: [(String, String, String)] = [
    ("ExitButton", "xmark.circle", "Close"),
    ("OK", "checkmark.circle", "Confirm"),
    ("StartConvert", "arrow.left.arrow.right", "Convert"),
    ("ThumbUp", "hand.thumbsup", "Like")
]

func render(symbolName: String, description: String, pixelSize: Int, destination: URL) throws {
    let canvasSize = CGFloat(pixelSize)
    guard let source = NSImage(systemSymbolName: symbolName, accessibilityDescription: description) else {
        throw NSError(domain: "ToolbarIconGenerator", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Missing SF Symbol: \(symbolName)"])
    }
    let configured = source.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: canvasSize * 0.62, weight: .medium)
    ) ?? source

    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                        pixelsWide: pixelSize,
                                        pixelsHigh: pixelSize,
                                        bitsPerSample: 8,
                                        samplesPerPixel: 4,
                                        hasAlpha: true,
                                        isPlanar: false,
                                        colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0,
                                        bitsPerPixel: 0) else {
        throw NSError(domain: "ToolbarIconGenerator", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap"])
    }
    bitmap.size = NSSize(width: canvasSize, height: canvasSize)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)).fill()
    NSColor(calibratedWhite: 0.30, alpha: 1).set()
    let symbolSize = min(canvasSize * 0.70, max(configured.size.width, configured.size.height))
    let rect = NSRect(x: (canvasSize - symbolSize) / 2,
                      y: (canvasSize - symbolSize) / 2,
                      width: symbolSize,
                      height: symbolSize)
    configured.isTemplate = true
    configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ToolbarIconGenerator", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try data.write(to: destination, options: .atomic)
}

for (name, symbol, description) in icons {
    for (suffix, pixels) in [(".png", 50), ("@2x.png", 100)] {
        let destination = resources.appendingPathComponent(name + suffix)
        try render(symbolName: symbol, description: description,
                   pixelSize: pixels, destination: destination)
    }
}
