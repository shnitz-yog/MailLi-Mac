// Draws the app icon and the DMG window background.
// usage: swift make_art.swift <out dir>
//   → icon_1024.png, dmg_background.png (640×480), dmg_background@2x.png (1280×960)
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func png(_ size: NSSize, scale: CGFloat = 1, _ draw: (CGRect) -> Void) -> Data {
    let px = NSSize(width: size.width * scale, height: size.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px.width), pixelsHigh: Int(px.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// MARK: icon – original artwork: sky tile, white envelope, red heart, little sun
let icon = png(NSSize(width: 1024, height: 1024)) { r in
    let tile = NSBezierPath(roundedRect: r.insetBy(dx: 100, dy: 100), xRadius: 185, yRadius: 185)
    NSGradient(starting: c(0x8EDBFA), ending: c(0x3FA9E6))!.draw(in: tile, angle: -90)
    // sun
    c(0xF7D970).setFill(); NSBezierPath(ovalIn: CGRect(x: 640, y: 640, width: 200, height: 200)).fill()
    // envelope
    let env = CGRect(x: 220, y: 290, width: 584, height: 400)
    let body = NSBezierPath(roundedRect: env, xRadius: 36, yRadius: 36)
    NSColor.white.setFill(); body.fill()
    c(0x1F3A93).setStroke(); body.lineWidth = 22; body.stroke()
    let flap = NSBezierPath()
    flap.move(to: CGPoint(x: env.minX + 30, y: env.maxY - 24))
    flap.line(to: CGPoint(x: env.midX, y: env.minY + 170))
    flap.line(to: CGPoint(x: env.maxX - 30, y: env.maxY - 24))
    flap.lineWidth = 22; flap.lineJoinStyle = .round; flap.lineCapStyle = .round; flap.stroke()
    // heart
    let h = NSBezierPath()
    let cx = env.midX, cy = env.minY + 110, s: CGFloat = 70
    h.move(to: CGPoint(x: cx, y: cy - s))
    h.curve(to: CGPoint(x: cx - s * 1.1, y: cy + s * 0.35), controlPoint1: CGPoint(x: cx - s * 0.4, y: cy - s * 0.55), controlPoint2: CGPoint(x: cx - s * 1.1, y: cy - s * 0.25))
    h.curve(to: CGPoint(x: cx, y: cy + s * 0.55), controlPoint1: CGPoint(x: cx - s * 1.1, y: cy + s * 1.05), controlPoint2: CGPoint(x: cx - s * 0.2, y: cy + s * 1.05))
    h.curve(to: CGPoint(x: cx + s * 1.1, y: cy + s * 0.35), controlPoint1: CGPoint(x: cx + s * 0.2, y: cy + s * 1.05), controlPoint2: CGPoint(x: cx + s * 1.1, y: cy + s * 1.05))
    h.curve(to: CGPoint(x: cx, y: cy - s), controlPoint1: CGPoint(x: cx + s * 1.1, y: cy - s * 0.25), controlPoint2: CGPoint(x: cx + s * 0.4, y: cy - s * 0.55))
    c(0xE53935).setFill(); h.fill()
}
try! icon.write(to: URL(fileURLWithPath: out + "/icon_1024.png"))

// MARK: DMG background – Hebrew instructions + arrows, app on the left, Applications on the right
func background(_ scale: CGFloat) -> Data {
    png(NSSize(width: 640, height: 480), scale: scale) { r in
        NSGradient(starting: c(0xFFFFFF), ending: c(0xD6F4FF))!.draw(in: r, angle: -90)
        c(0xF7D970).setFill(); NSBezierPath(rect: CGRect(x: 0, y: r.height - 10, width: r.width, height: 10)).fill()
        let p = NSMutableParagraphStyle(); p.alignment = .center; p.baseWritingDirection = .rightToLeft
        func text(_ s: String, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, _ col: NSColor) {
            let f = NSFont.systemFont(ofSize: size, weight: weight)
            let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: col, .paragraphStyle: p])
            a.draw(in: CGRect(x: 20, y: y, width: r.width - 40, height: size * 1.5))
        }
        text("כדי להתקין, גוררים את MailLi לתיקיית Applications", r.height - 72, 22, .bold, c(0x1F3A93))
        text("To install, drag MailLi to Applications", r.height - 100, 14, .regular, c(0x1F3A93, 0.6))
        // arrows between the icons (app at x=160, Applications at x=480, centre y=190 from top)
        let y = r.height - 190
        for (i, a) in [0.35, 0.6, 1.0].enumerated() {
            let x = 290 + CGFloat(i) * 26
            let ch = NSBezierPath()
            ch.move(to: CGPoint(x: x, y: y + 16)); ch.line(to: CGPoint(x: x + 16, y: y)); ch.line(to: CGPoint(x: x, y: y - 16))
            ch.lineWidth = 6; ch.lineCapStyle = .round; ch.lineJoinStyle = .round
            c(0x3DA7D9, a).setStroke(); ch.stroke()
        }
        text("פעם ראשונה? פותחים את קובץ ההוראות 👇", r.height - 305, 15, .semibold, c(0x1F3A93, 0.75))
    }
}
try! background(1).write(to: URL(fileURLWithPath: out + "/dmg_background.png"))
try! background(2).write(to: URL(fileURLWithPath: out + "/dmg_background@2x.png"))
print("art written to \(out)")
