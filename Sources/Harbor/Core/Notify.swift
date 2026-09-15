import Foundation

/// `osascript display notification`: `UNUserNotificationCenter` does not deliver
/// from an ad-hoc signed app.
enum Notify {
    static func post(title: String, message: String) {
        let script = "display notification \(escaped(message)) with title \(escaped(title))"
        Shell.runDetached("/usr/bin/osascript", ["-e", script])
    }

    private static func escaped(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
