#!/usr/bin/env swift
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

func draw(_ px: Int) -> NSImage {
    let size = CGFloat(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size / 1024

    let plate = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                             xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: plateTop, ending: plateBottom)?.draw(in: plate, angle: -90)

    func arrow(y: CGFloat, from: CGFloat, to: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: from * s, y: y * s))
        path.line(to: NSPoint(x: to * s, y: y * s))
        let sign: CGFloat = to > from ? -1 : 1
        path.move(to: NSPoint(x: (to + sign * 82) * s, y: (y + 82) * s))
        path.line(to: NSPoint(x: to * s, y: y * s))
        path.line(to: NSPoint(x: (to + sign * 82) * s, y: (y - 82) * s))
        path.lineWidth = 52 * s
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        return path
    }

    color(0xFFFFFF, 0.95).setStroke()
    arrow(y: 596, from: 300, to: 690).stroke()
    arrow(y: 428, from: 724, to: 334).stroke()

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
