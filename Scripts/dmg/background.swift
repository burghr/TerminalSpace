// Draws the background of the TerminalSpace disk image window: the colors of
// the app icon (a dark screen and a green cursor),
// an arrow from the app icon to the Applications folder, and one line of text.
// Usage: swift background.swift <out.png> <scale>   (scale 1 or 2)
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write(Data("Usage: background.swift <out.png> <scale>\n".utf8))
    exit(1)
}
let size = CGSize(width: 640, height: 400)          // Points; the same as the window in make-dmg.sh
let pixels = CGSize(width: size.width * scale, height: size.height * scale)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The background: the screen of the app icon, dark at the bottom, a little lighter at the top.
let bottom = NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
let top = NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

// A thin line in the cursor green of the app icon at the top.
NSColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1).setFill()
NSRect(x: 0, y: size.height - 4, width: size.width, height: 4).fill()

// The arrow between the two icons (icon centers at x 170 and 470, y 200 from the top).
let y = size.height - 200
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 262, y: y))
arrow.line(to: NSPoint(x: 368, y: y))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
let head = NSBezierPath()
head.move(to: NSPoint(x: 352, y: y + 16))
head.line(to: NSPoint(x: 372, y: y))
head.line(to: NSPoint(x: 352, y: y - 16))
head.lineWidth = 5
head.lineCapStyle = .round
head.lineJoinStyle = .round
NSColor(white: 0.70, alpha: 1).setStroke()
arrow.stroke()
head.stroke()

// The instruction under the icons.
let text = "Drag TerminalSpace to Applications"
let style = NSMutableParagraphStyle()
style.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .medium),
    .foregroundColor: NSColor(white: 0.85, alpha: 1),
    .paragraphStyle: style,
]
text.draw(in: NSRect(x: 0, y: 52, width: size.width, height: 26), withAttributes: attributes)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
