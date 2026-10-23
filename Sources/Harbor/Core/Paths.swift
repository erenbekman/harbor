import Foundation

enum Paths {
    private static let stateFiles = ["projects.json", "tmux.conf", "magic.log"]

    static let support: URL = {
        let override = ProcessInfo.processInfo.environment["HARBOR_SUPPORT_DIR"]
        let base = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Harbor", isDirectory: true)
        let existed = FileManager.default.fileExists(atPath: base.path)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if override == nil || !existed {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        }
        for name in stateFiles {
            let file = base.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
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
