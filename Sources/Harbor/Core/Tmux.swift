import Foundation

/// Services run inside tmux so they outlive the app: closing the window — or
/// quitting — leaves `npm run dev` running, and reopening shows it still up.
///
/// Always a fixed `-S <socket>`, never `-L`: a GUI process and a login shell see
/// different `TMUX_TMPDIR` values and would end up on two separate servers.
enum Tmux {

    static let socketPath = "/tmp/harbor-\(getuid()).sock"

    static let path: String? = Shell.findExecutable([
        "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux",
        "/opt/local/bin/tmux", "/usr/bin/tmux",
    ]) ?? Shell.which("tmux")

    static var isAvailable: Bool { path != nil }

    static func ensureConfig() {
        let body = """
        set -g status off
        set -sg escape-time 0
        set -g default-terminal "screen-256color"
        set -g history-limit 20000
        set -g destroy-unattached off
        set -g mouse off
        """
        try? body.write(to: Paths.tmuxConfig, atomically: true, encoding: .utf8)
    }

    struct PaneState {
        let dead: Bool
        let exitCode: Int?
        let pid: Int32
    }

    /// Every session's pane state in ONE call — a fork per service, twice a
    /// second, is exactly the cost this avoids.
    static func paneStates() -> [String: PaneState] {
        let r = run(["list-panes", "-a", "-F",
                     "#{session_name}\t#{pane_dead}\t#{pane_dead_status}\t#{pane_pid}"])
        guard r.status == 0 else { return [:] }
        var out: [String: PaneState] = [:]
        for line in r.out.split(separator: "\n") {
            let f = line.components(separatedBy: "\t")
            guard f.count >= 4, !f[0].isEmpty else { continue }
            let dead = f[1] != "0"
            out[f[0]] = PaneState(dead: dead,
                                  exitCode: dead ? Int(f[2]) : nil,
                                  pid: Int32(f[3]) ?? 0)
        }
        return out
    }

    static func paneState(_ session: String) -> PaneState? {
        let r = run(["display-message", "-p", "-t", session,
                     "#{pane_dead}\t#{pane_dead_status}\t#{pane_pid}"])
        guard r.status == 0 else { return nil }
        let f = r.out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard let first = f.first, !first.isEmpty else { return nil }
        let dead = first != "0"
        return PaneState(dead: dead,
                         exitCode: dead && f.count > 1 ? Int(f[1]) : nil,
                         pid: f.count > 2 ? (Int32(f[2]) ?? 0) : 0)
    }

    static func exists(_ name: String) -> Bool {
        run(["has-session", "-t", name]).status == 0
    }

    /// `remain-on-exit` is set from INSIDE the pane, before the command runs:
    /// setting it from outside a moment later is a race a fast-failing service
    /// wins, and its output — the reason it failed — dies with the session.
    static func start(session: String, cwd: String, command: String) {
        guard let tmux = path else { return }
        let inner = "\(Shell.quoted(tmux)) set-option remain-on-exit on 2>/dev/null; "
            + "cd \(Shell.quoted(cwd)) && \(command)"
        let shell = "exec /bin/zsh -l -i -c \(Shell.quoted(inner))"
        _ = run(["new-session", "-d", "-s", session, "-x", "200", "-y", "50", shell])
    }

    static func interrupt(_ session: String) {
        _ = run(["send-keys", "-t", session, "C-c"])
    }

    static func kill(_ session: String) {
        _ = run(["kill-session", "-t", session])
    }

    static func capture(_ session: String, lines: Int = 400) -> String {
        let r = run(["capture-pane", "-p", "-J", "-S", "-\(max(1, lines))", "-t", session])
        return r.status == 0 ? r.out : ""
    }

    @discardableResult
    private static func run(_ args: [String]) -> (status: Int32, out: String) {
        guard let tmux = path else { return (-1, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tmux)
        p.arguments = ["-S", socketPath, "-f", Paths.tmuxConfig.path] + args
        // A UTF-8 locale, forced: in the C locale tmux turns every byte it thinks
        // unprintable — the TAB these formats separate fields with included — into
        // `_`, and the parse below collapses to one field.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Shell.userPath
        if !(environment["LANG"] ?? "").uppercased().contains("UTF-8") {
            environment["LANG"] = "en_US.UTF-8"
        }
        p.environment = environment
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return (-1, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        done.wait()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
