import AppKit

/// Menu bar icons. Both are template images so they follow light/dark menu bars.
/// Passive: plain laptop outline. Active: laptop with a bolt drawn on the screen.
enum Icons {
    static let size = NSSize(width: 22, height: 18)

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    }

    static let passive: NSImage = make(active: false)
    static let active: NSImage = make(active: true)

    private static func make(active: Bool) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            guard let laptop = symbol("laptopcomputer", pointSize: 15, weight: active ? .semibold : .regular) else {
                return false
            }
            let ls = laptop.size
            let lRect = NSRect(x: (rect.width - ls.width) / 2, y: (rect.height - ls.height) / 2,
                               width: ls.width, height: ls.height)
            laptop.draw(in: lRect)

            if active, let bolt = symbol("bolt.fill", pointSize: 8, weight: .black) {
                let bs = bolt.size
                // Centre the bolt inside the screen area (upper ~70% of the glyph).
                let screenMidY = lRect.minY + lRect.height * 0.58
                let bRect = NSRect(x: lRect.midX - bs.width / 2, y: screenMidY - bs.height / 2,
                                   width: bs.width, height: bs.height)
                bolt.draw(in: bRect)
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = active ? "Close The Lid: active" : "Close The Lid: passive"
        return img
    }
}
