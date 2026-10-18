import Foundation

enum Paths {
    static let support: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harbor", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: base.appendingPathComponent(name).path)
        }
        return base
    }()

    static var projectsFile: URL { support.appendingPathComponent("projects.json") }
    static var tmuxConfig: URL { support.appendingPathComponent("tmux.conf") }

    static func writeAtomically(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
