import AppKit

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let plateTop = color(0xE2A184)
let plateBottom = color(0xC9765A)
let accent = color(0xFFFFFF)
let ink = color(0xFFFFFF)

func draw(_ px: Int) -> NSBitmapImageRep {
    let size = CGFloat(px)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("no bitmap") }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let plate = NSBezierPath(roundedRect: NSRect(x: 100 * size / 1024, y: 100 * size / 1024,
                                                 width: 824 * size / 1024, height: 824 * size / 1024),
                             xRadius: 185 * size / 1024, yRadius: 185 * size / 1024)
    NSGradient(starting: plateTop, ending: plateBottom)?.draw(in: plate, angle: -90)

    let inset = size * 0.17
    NSGraphicsContext.current?.saveGraphicsState()
    let shift = NSAffineTransform()
    shift.translateX(by: inset, yBy: inset)
    shift.concat()
    Mark.draw(size: size - inset * 2, filled: true, stroke: ink, head: accent)
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let out = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: out)
try? fm.createDirectory(at: out, withIntermediateDirectories: true)

for (name, px) in sizes {
    guard let png = draw(px).representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: out.appendingPathComponent("\(name).png"))
}
print("✓ AppIcon.iconset")
