// Renders the TubeVault app icon into an .iconset folder. Usage: swift make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Squircle background with a red gradient.
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 1.0, green: 0.27, blue: 0.27, alpha: 1),
                        NSColor(red: 0.78, green: 0.05, blue: 0.12, alpha: 1)])!
        .draw(in: bg, angle: -90)

    // Play triangle.
    let c = NSPoint(x: s / 2, y: s * 0.56)
    let r = rect.width * 0.2
    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: c.x - r * 0.75, y: c.y + r))
    tri.line(to: NSPoint(x: c.x - r * 0.75, y: c.y - r))
    tri.line(to: NSPoint(x: c.x + r * 1.0, y: c.y))
    tri.close()
    NSColor.white.setFill()
    tri.fill()

    // Download tray underneath.
    let tray = NSBezierPath()
    let w = rect.width * 0.46, y = s * 0.27
    tray.move(to: NSPoint(x: s / 2 - w / 2, y: y + w * 0.14))
    tray.line(to: NSPoint(x: s / 2 - w / 2, y: y))
    tray.line(to: NSPoint(x: s / 2 + w / 2, y: y))
    tray.line(to: NSPoint(x: s / 2 + w / 2, y: y + w * 0.14))
    tray.lineWidth = rect.width * 0.045
    tray.lineCapStyle = .round
    tray.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.9).setStroke()
    tray.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
