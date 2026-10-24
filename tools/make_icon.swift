// Renders the Chorden app icon into an .iconset folder.
// Usage: swift tools/make_icon.swift <out.iconset> && iconutil -c icns <out.iconset>
//
// The mark is unison made visible: two tones at the same pitch, traced against each other as on an oscilloscope
// (a Lissajous figure), hold still as a single ellipse. That stillness is what "in tune" looks like.
// The trace turns from white to green, a tone settling in tune.
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// x = sin(t + 3π/4), y = sin(t): the unison figure, an ellipse on the falling diagonal with semi-axes
/// r·√2·cos(π/8) and r·√2·sin(π/8). Drawn as the band between two ellipses ±d from that curve, which keeps
/// the inner tips round where a constant-width stroke would pinch them.
func unison(radius r: CGFloat, halfWidth d: CGFloat) -> CGPath {
    let a = r * sqrt(2) * cos(.pi / 8), b = r * sqrt(2) * sin(.pi / 8)
    let t = CGAffineTransform(translationX: 512, y: 512).rotated(by: -.pi / 4)
    let ring = CGMutablePath()
    for s in [d, -d] {
        ring.addEllipse(in: CGRect(x: -(a + s), y: -(b + s), width: 2 * (a + s), height: 2 * (b + s)), transform: t)
    }
    return ring
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // Base squircle with drop shadow (macOS icon grid: 824pt body inside 1024 canvas).
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x0E0F12).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x272A31), ending: color(0x0B0C0F))!.draw(in: body, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(starting: color(0xFFFFFF, 0.06), ending: color(0xFFFFFF, 0))!
        .draw(fromCenter: NSPoint(x: 300, y: 820), radius: 0, toCenter: NSPoint(x: 300, y: 820), radius: 600, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // The ellipse, filled with a white-to-green gradient; heavier at small sizes so it stays crisp.
    let width: CGFloat = px <= 16 ? 112 : (px <= 32 ? 92 : (px <= 64 ? 78 : 68))
    let ring = unison(radius: 218, halfWidth: width / 2)
    cg.saveGState()
    cg.addPath(ring)
    cg.clip(using: .evenOdd)
    NSGradient(starting: color(0xF4F4F4), ending: color(0x34C77B))!.draw(in: ring.boundingBoxOfPath, angle: -45)
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
