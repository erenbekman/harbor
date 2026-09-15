import SwiftUI

enum Theme {
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
        Color(red: 0.85, green: 0.44, blue: 0.24),
        Color(red: 0.29, green: 0.56, blue: 0.89),
        Color(red: 0.27, green: 0.68, blue: 0.47),
        Color(red: 0.76, green: 0.33, blue: 0.55),
        Color(red: 0.52, green: 0.44, blue: 0.85),
        Color(red: 0.86, green: 0.66, blue: 0.22),
        Color(red: 0.36, green: 0.65, blue: 0.70),
        Color(red: 0.50, green: 0.52, blue: 0.58),
    ]

    static func tint(_ index: Int) -> Color {
        tints[((index % tints.count) + tints.count) % tints.count]
    }
}

extension ServiceStatus {
    var color: Color {
        switch self {
        case .running: return Color(red: 0.24, green: 0.72, blue: 0.40)
        case .starting: return Color(red: 0.92, green: 0.70, blue: 0.20)
        case .failed: return Color(red: 0.87, green: 0.33, blue: 0.29)
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
