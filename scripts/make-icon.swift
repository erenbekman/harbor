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

let plateTop = color(0x3C424B)
let plateBottom = color(0x1B1F24)
let accent = color(0x0A84FF)
let ink = color(0xFFFFFF, 0.95)

func draw(_ px: Int) -> NSImage {
    let size = CGFloat(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let plate = NSBezierPath(roundedRect: NSRect(x: 100 * size / 1024, y: 100 * size / 1024,
                                                 width: 824 * size / 1024, height: 824 * size / 1024),
                             xRadius: 185 * size / 1024, yRadius: 185 * size / 1024)
    NSGradient(starting: plateTop, ending: plateBottom)?.draw(in: plate, angle: -90)

    let inset = size * 0.22
    let markSize = size - inset * 2
    NSGraphicsContext.current?.saveGraphicsState()
    let shift = NSAffineTransform()
    shift.translateX(by: inset, yBy: inset)
    shift.concat()
    Mark.draw(size: markSize, filled: true, stroke: ink, head: accent)
    NSGraphicsContext.current?.restoreGraphicsState()

    image.unlockFocus()
    return image
}

let fm = FileManager.default
let out = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: out)
try? fm.createDirectory(at: out, withIntermediateDirectories: true)

for (name, px) in sizes {
    let image = draw(px)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: out.appendingPathComponent("\(name).png"))
}
print("✓ AppIcon.iconset")
