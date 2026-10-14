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

let plateTop = color(0x232B36)
let plateBottom = color(0x0F141A)
let panelFill = color(0x161C24)
let chipIdle = color(0x2B3540)
let accent = color(0xFF9E20)
let accentDim = color(0xC9741A)

func draw(_ px: Int) -> NSImage {
    let size = CGFloat(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size / 1024

    func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x * s, y: y * s, width: w * s, height: h * s),
                     xRadius: r * s, yRadius: r * s)
    }

    let plate = rounded(100, 100, 824, 824, 185)
    NSGradient(starting: plateTop, ending: plateBottom)?.draw(in: plate, angle: -90)

    let panel = rounded(352, 212, 320, 600, 104)
    panelFill.setFill()
    panel.fill()
    color(0xFFFFFF, 0.10).setStroke()
    panel.lineWidth = 3 * s
    panel.stroke()

    chipIdle.setFill()
    rounded(437, 246, 150, 150, 46).fill()
    rounded(437, 422, 150, 150, 46).fill()

    let berth = rounded(437, 628, 150, 150, 46)
    NSGradient(starting: accent, ending: accentDim)?.draw(in: berth, angle: -90)

    accent.setFill()
    rounded(472, 598, 80, 18, 9).fill()

    let white = color(0xFFFFFF, 0.96)
    white.setFill()

    if px <= 64 {
        let sail = NSBezierPath()
        sail.move(to: NSPoint(x: 512 * s, y: 762 * s))
        sail.line(to: NSPoint(x: 512 * s, y: 652 * s))
        sail.line(to: NSPoint(x: 578 * s, y: 652 * s))
        sail.close()
        sail.fill()
        let mast = NSBezierPath()
        mast.move(to: NSPoint(x: 500 * s, y: 744 * s))
        mast.line(to: NSPoint(x: 500 * s, y: 652 * s))
        mast.line(to: NSPoint(x: 450 * s, y: 652 * s))
        mast.close()
        mast.fill()
        image.unlockFocus()
        return image
    }

    let mainSail = NSBezierPath()
    mainSail.move(to: NSPoint(x: 515 * s, y: 752 * s))
    mainSail.line(to: NSPoint(x: 515 * s, y: 680 * s))
    mainSail.line(to: NSPoint(x: 565 * s, y: 680 * s))
    mainSail.close()
    mainSail.fill()

    let jib = NSBezierPath()
    jib.move(to: NSPoint(x: 503 * s, y: 742 * s))
    jib.line(to: NSPoint(x: 503 * s, y: 680 * s))
    jib.line(to: NSPoint(x: 461 * s, y: 680 * s))
    jib.close()
    jib.fill()

    let hull = NSBezierPath()
    hull.move(to: NSPoint(x: 455 * s, y: 668 * s))
    hull.line(to: NSPoint(x: 569 * s, y: 668 * s))
    hull.line(to: NSPoint(x: 549 * s, y: 646 * s))
    hull.line(to: NSPoint(x: 475 * s, y: 646 * s))
    hull.close()
    hull.fill()

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
