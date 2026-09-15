import Foundation

enum Paths {
    static let support: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harbor", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static var projectsFile: URL { support.appendingPathComponent("projects.json") }
    static var tmuxConfig: URL { support.appendingPathComponent("tmux.conf") }

    static func writeAtomically(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
    }
}
