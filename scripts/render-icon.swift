import AppKit

// Grove's original vector artwork. Render locally; no external image service or fonts.
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let tile = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876), xRadius: 196, yRadius: 196)
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState(); shadow.set()
NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.12, alpha: 1).setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(calibratedRed: 0.17, green: 0.25, blue: 0.21, alpha: 1),
           ending: NSColor(calibratedRed: 0.045, green: 0.09, blue: 0.085, alpha: 1))!.draw(in: tile, angle: -70)
NSColor.white.withAlphaComponent(0.11).setStroke(); tile.lineWidth = 3; tile.stroke()

// Three luminous leaves share a branch; their negative space reads as a code fork.
func leaf(_ start: NSPoint, _ c1: NSPoint, _ c2: NSPoint, _ tip: NSPoint,
          _ c3: NSPoint, _ c4: NSPoint, _ color: NSColor) {
    let path = NSBezierPath(); path.move(to: start)
    path.curve(to: tip, controlPoint1: c1, controlPoint2: c2)
    path.curve(to: start, controlPoint1: c3, controlPoint2: c4); path.close()
    color.setFill(); path.fill()
}
let green = NSColor(calibratedRed: 0.71, green: 0.9, blue: 0.51, alpha: 1)
leaf(NSPoint(x: 503, y: 504), NSPoint(x: 375, y: 476), NSPoint(x: 277, y: 550), NSPoint(x: 285, y: 700),
     NSPoint(x: 447, y: 714), NSPoint(x: 530, y: 640), green)
leaf(NSPoint(x: 523, y: 573), NSPoint(x: 476, y: 705), NSPoint(x: 541, y: 798), NSPoint(x: 678, y: 809),
     NSPoint(x: 711, y: 677), NSPoint(x: 641, y: 589), NSColor(calibratedRed: 0.84, green: 0.96, blue: 0.64, alpha: 1))
leaf(NSPoint(x: 545, y: 466), NSPoint(x: 554, y: 589), NSPoint(x: 661, y: 638), NSPoint(x: 770, y: 588),
     NSPoint(x: 739, y: 454), NSPoint(x: 647, y: 417), NSColor(calibratedRed: 0.47, green: 0.75, blue: 0.43, alpha: 1))
let branch = NSBezierPath(); branch.move(to: NSPoint(x: 470, y: 310))
branch.curve(to: NSPoint(x: 553, y: 650), controlPoint1: NSPoint(x: 484, y: 421), controlPoint2: NSPoint(x: 520, y: 568))
branch.lineWidth = 34; branch.lineCapStyle = .round; green.setStroke(); branch.stroke()
let prompt = NSBezierPath(); prompt.move(to: NSPoint(x: 284, y: 344)); prompt.line(to: NSPoint(x: 345, y: 292)); prompt.line(to: NSPoint(x: 284, y: 240))
prompt.lineWidth = 22; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round
NSColor(calibratedRed: 0.58, green: 0.7, blue: 0.62, alpha: 1).setStroke(); prompt.stroke()
let cursor = NSBezierPath(); cursor.move(to: NSPoint(x: 579, y: 264)); cursor.line(to: NSPoint(x: 705, y: 264)); cursor.lineWidth = 20; cursor.lineCapStyle = .round; cursor.stroke()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
try data.write(to: URL(fileURLWithPath: output), options: .atomic)
print(output)
