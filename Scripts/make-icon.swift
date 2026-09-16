// Draws the TerminalSpace icon and writes Resources/AppIcon.icns.
// Run: swift Scripts/make-icon.swift
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024  // The design uses a 1024 point grid.

    // The macOS icon grid: an 824 point body with a 100 point margin.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let radius = 185 * s

    // Shadow under the body.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedWhite: 0.55, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Metal bezel.
    let bezel = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGradient(starting: NSColor(calibratedWhite: 0.86, alpha: 1),
               ending: NSColor(calibratedWhite: 0.58, alpha: 1))!.draw(in: bezel, angle: -90)

    // Dark screen.
    let screen = body.insetBy(dx: 34 * s, dy: 34 * s)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: radius - 34 * s, yRadius: radius - 34 * s)
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.20, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1))!.draw(in: screenPath, angle: -90)

    // Soft reflection on the top half of the screen.
    NSGraphicsContext.saveGraphicsState()
    screenPath.addClip()
    let glare = NSRect(x: screen.minX, y: screen.midY, width: screen.width, height: screen.height / 2)
    NSGradient(starting: NSColor.white.withAlphaComponent(0.07),
               ending: NSColor.white.withAlphaComponent(0))!.draw(in: glare, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The "~" prompt and a cursor block in the top left of the screen.
    let text = NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
    let font = NSFont.monospacedSystemFont(ofSize: 330 * s, weight: .bold)
    let tilde = NSAttributedString(string: "~", attributes: [.font: font, .foregroundColor: text])
    let tildeSize = tilde.size()
    let origin = NSPoint(x: screen.minX + 60 * s, y: screen.maxY - 40 * s - tildeSize.height)
    tilde.draw(at: origin)

    // Center the cursor on the middle line of the "~" glyph.
    let glyphBounds = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(tilde), .useGlyphPathBounds)
    let tildeMid = origin.y - font.descender + glyphBounds.midY
    let cursorHeight: CGFloat = 120 * s
    let cursor = NSRect(x: origin.x + tildeSize.width + 10 * s, y: tildeMid - cursorHeight / 2,
                        width: 62 * s, height: cursorHeight)
    NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(roundedRect: cursor, xRadius: 8 * s, yRadius: 8 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}
try! drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
