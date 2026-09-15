import AppKit

enum Terminals {
    /// Hands a tmux session to a real terminal: the log panel is read-only, and a
    /// service that asks a question can only be answered at its own prompt.
    static func attach(session: String) {
        guard let tmux = Tmux.path else { return }
        let script = """
        #!/bin/zsh
        exec \(Shell.quoted(tmux)) -S \(Shell.quoted(Tmux.socketPath)) attach -t \(Shell.quoted(session))
        """
        let url = Paths.support.appendingPathComponent("attach-\(session).command")
        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        open(url, with: terminalApps)
    }

    static func openInEditor(path: String) {
        open(URL(fileURLWithPath: path), with: editorApps)
    }

    /// Whatever is squatting on the port, on the user's say-so.
    static func free(pid: Int32) {
        Shell.runDetached("/bin/kill", ["-TERM", String(pid)])
    }

    /// Who is holding the port: pid and the command's name.
    static func holder(ofPort port: Int) -> (pid: Int32, command: String)? {
        let r = Shell.run("/usr/sbin/lsof",
                          ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpc"])
        guard r.status == 0 else { return nil }
        var pid: Int32?
        var command: String?
        for line in r.output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            if tag == "p" { pid = Int32(line.dropFirst()) }
            if tag == "c" { command = String(line.dropFirst()) }
        }
        guard let pid else { return nil }
        return (pid, command ?? "?")
    }

    private static let terminalApps = ["iTerm", "Terminal"]
    private static let editorApps = ["Cursor", "Visual Studio Code", "Sublime Text", "Xcode"]

    private static func open(_ url: URL, with apps: [String]) {
        for name in apps {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID(for: name))
                ?? applicationURL(named: name) else { continue }
            NSWorkspace.shared.open([url], withApplicationAt: app,
                                    configuration: NSWorkspace.OpenConfiguration())
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func applicationURL(named name: String) -> URL? {
        let candidates = ["/Applications/\(name).app",
                          NSHomeDirectory() + "/Applications/\(name).app"]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func bundleID(for name: String) -> String {
        switch name {
        case "iTerm": return "com.googlecode.iterm2"
        case "Terminal": return "com.apple.Terminal"
        case "Cursor": return "com.todesktop.230313mzl4w4u92"
        case "Visual Studio Code": return "com.microsoft.VSCode"
        case "Sublime Text": return "com.sublimetext.4"
        case "Xcode": return "com.apple.dt.Xcode"
        default: return name
        }
    }
}
