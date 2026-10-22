import AppKit

enum Mark {
    static func image(size: CGFloat, filled: Bool, color: NSColor = .labelColor) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            draw(size: size, filled: filled, stroke: color, head: color)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func draw(size: CGFloat, filled: Bool, stroke: NSColor, head: NSColor) {
        let s = size / 24
        let width = max(1, 2.4 * s)

        let circle = NSBezierPath(ovalIn: NSRect(x: (12 - 3) * s, y: (15.8 - 3) * s,
                                                 width: 6 * s, height: 6 * s))
        circle.lineWidth = width
        if filled {
            head.setFill()
            circle.fill()
        } else {
            head.setStroke()
            circle.stroke()
        }

        stroke.setStroke()

        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 12 * s, y: 12.8 * s))
        stem.line(to: NSPoint(x: 12 * s, y: 8.4 * s))
        stem.lineWidth = width
        stem.lineCapStyle = .round
        stem.stroke()

        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: 3.2 * s, y: 6.4 * s))
        wave.curve(to: NSPoint(x: 9.2 * s, y: 6.4 * s),
                   controlPoint1: NSPoint(x: 5.2 * s, y: 8 * s),
                   controlPoint2: NSPoint(x: 7.2 * s, y: 8 * s))
        wave.curve(to: NSPoint(x: 15.2 * s, y: 6.4 * s),
                   controlPoint1: NSPoint(x: 11.2 * s, y: 4.8 * s),
                   controlPoint2: NSPoint(x: 13.2 * s, y: 4.8 * s))
        wave.curve(to: NSPoint(x: 20.8 * s, y: 6.4 * s),
                   controlPoint1: NSPoint(x: 17.2 * s, y: 8 * s),
                   controlPoint2: NSPoint(x: 19 * s, y: 8 * s))
        wave.lineWidth = width
        wave.lineCapStyle = .round
        wave.lineJoinStyle = .round
        wave.stroke()
    }
}
