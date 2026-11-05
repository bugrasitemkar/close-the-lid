// Renders the app icon (1024x1024 PNG). Usage: swift scripts/make-icon.swift out.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = NSRect(x: 0, y: 0, width: px, height: px)
// macOS icon grid: ~824pt rounded square centred in 1024.
let tile = canvas.insetBy(dx: 100, dy: 100)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.32, alpha: 1),
                    NSColor(calibratedRed: 0.25, green: 0.36, blue: 0.85, alpha: 1)])!
    .draw(in: path, angle: 90)

func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight, _ colors: [NSColor]) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(.init(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
}

let laptop = symbol("laptopcomputer", 420, .medium, [.white, NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.26, alpha: 1)])
let ls = laptop.size
let lRect = NSRect(x: (CGFloat(px) - ls.width) / 2, y: (CGFloat(px) - ls.height) / 2 - 10,
                   width: ls.width, height: ls.height)
laptop.draw(in: lRect)

let bolt = symbol("bolt.fill", 190, .black, [NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.20, alpha: 1)])
let bs = bolt.size
bolt.draw(in: NSRect(x: lRect.midX - bs.width / 2, y: lRect.minY + lRect.height * 0.58 - bs.height / 2,
                     width: bs.width, height: bs.height))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
