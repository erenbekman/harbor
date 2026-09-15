#!/usr/bin/env swift
import AppKit

// The app icon is the app: a rail of project chips, one of them running.

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let plateTop = color(0x1D3355)
let plateBottom = color(0x102037)
let rail = color(0x0B1626)
let chip = color(0x3D5A80)
let accent = color(0xE07A3F)
let green = color(0x3EB85F)

func draw(_ px: Int) -> NSImage {
    let size = CGFloat(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size / 1024

    let plate = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                             xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: plateTop, ending: plateBottom)?.draw(in: plate, angle: -90)

    let railRect = NSRect(x: 190 * s, y: 190 * s, width: 210 * s, height: 644 * s)
    rail.setFill()
    NSBezierPath(roundedRect: railRect, xRadius: 72 * s, yRadius: 72 * s).fill()

    let chips: [(CGFloat, NSColor)] = [(640, accent), (460, chip), (280, chip)]
    for (y, fill) in chips {
        fill.setFill()
        NSBezierPath(roundedRect: NSRect(x: 235 * s, y: y * s, width: 120 * s, height: 120 * s),
                     xRadius: 36 * s, yRadius: 36 * s).fill()
    }

    let panel = NSRect(x: 452 * s, y: 300 * s, width: 372 * s, height: 424 * s)
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: panel, xRadius: 56 * s, yRadius: 56 * s).fill()

    for (index, y) in [560, 420].enumerated() {
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: NSRect(x: 500 * s, y: CGFloat(y) * s, width: 276 * s, height: 96 * s),
                     xRadius: 30 * s, yRadius: 30 * s).fill()
        (index == 0 ? green : NSColor.white.withAlphaComponent(0.3)).setFill()
        NSBezierPath(ovalIn: NSRect(x: 534 * s, y: CGFloat(y + 34) * s, width: 28 * s, height: 28 * s)).fill()
        NSColor.white.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: NSRect(x: 586 * s, y: CGFloat(y + 38) * s, width: 150 * s, height: 20 * s),
                     xRadius: 10 * s, yRadius: 10 * s).fill()
    }

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
