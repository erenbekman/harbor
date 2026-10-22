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
    static let base = Color(hex: 0x1F1F1F)
    static let raised = Color(hex: 0x282828)
    static let line = Color(hex: 0x343434)
    static let control = Color(hex: 0x323232)
    static let hover = Color.white.opacity(0.05)
    static let ink = Color(hex: 0xE3E3E3)
    static let muted = Color(hex: 0x8E8E8E)
    static let faint = Color(hex: 0x696969)
    static let accent = Color(hex: 0xD68F70)

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
