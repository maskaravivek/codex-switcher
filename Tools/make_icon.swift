import AppKit

// Renders a small "switch" (bidirectional arrows) template icon as PNG.
// Apple menu bar status icons are ~16-18pt template images. We draw on an
// 18pt canvas at 2x (36px) for crisp Retina rendering.
// Usage: swift make_icon.swift <output.png>

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write("usage: swift make_icon.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}

let points: CGFloat = 18
let px = 36 // 2x scale (Retina)
let scale = CGFloat(px) / points

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: px,
    pixelsHigh: px,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(1) }

let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high
ctx.cgContext.scaleBy(x: scale, y: scale)

let path = NSBezierPath()
path.lineWidth = 1.8
path.lineCapStyle = .round
path.lineJoinStyle = .round

// Center shaft
path.move(to: NSPoint(x: 2.5, y: 9))
path.line(to: NSPoint(x: 15.5, y: 9))

// Left arrowhead (points left)
path.move(to: NSPoint(x: 6.5, y: 5))
path.line(to: NSPoint(x: 2.5, y: 9))
path.line(to: NSPoint(x: 6.5, y: 13))

// Right arrowhead (points right)
path.move(to: NSPoint(x: 11.5, y: 5))
path.line(to: NSPoint(x: 15.5, y: 9))
path.line(to: NSPoint(x: 11.5, y: 13))

NSColor.black.setStroke()
path.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[1]))
print("wrote \(args[1]) (\(px)x\(px), \(points)pt @2x)")
