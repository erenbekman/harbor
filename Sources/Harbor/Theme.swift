import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let base = Color(hex: 0x272A2C)
    static let raised = Color(hex: 0x313335)
    static let sidebar = Color(hex: 0x2B3135)
    static let line = Color(hex: 0x3C3F41)
    static let control = Color(hex: 0x484D4E)
    static let button = Color(hex: 0x505050)
    static let ink = Color(hex: 0xF2F2F5)
    static let muted = Color(hex: 0x9A9DA0)
    static let accent = Color(hex: 0x0091FF)

    static let railWidth: CGFloat = 78
    static let railExpandedWidth: CGFloat = 196
    static let chipSize: CGFloat = 54
    static let corner: CGFloat = 15

    static let rail = Color(nsColor: .underPageBackgroundColor)
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)

    static let tints: [Color] = [
        Color(nsColor: .systemOrange),
        Color(nsColor: .systemBlue),
        Color(nsColor: .systemGreen),
        Color(nsColor: .systemPink),
        Color(nsColor: .systemPurple),
        Color(nsColor: .systemYellow),
        Color(nsColor: .systemTeal),
        Color(nsColor: .systemGray),
    ]

    static func tint(_ index: Int) -> Color {
        tints[((index % tints.count) + tints.count) % tints.count]
    }
}

extension ServiceStatus {
    var color: Color {
        switch self {
        case .running: return Color(nsColor: .systemGreen)
        case .starting: return Color(nsColor: .systemOrange)
        case .failed: return Color(nsColor: .systemRed)
        case .stopped: return Theme.secondary.opacity(0.55)
        }
    }

    func label(port: Int?) -> String {
        switch self {
        case .running: return port.map { "running · :\($0)" } ?? "running"
        case .starting: return "starting…"
        case .stopped: return "stopped"
        case .failed(let code): return code.map { "exited (\($0))" } ?? "exited"
        }
    }
}
