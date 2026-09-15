import Foundation

enum Shell {
    /// A GUI process inherits a minimal PATH from launchd, so node/php/tmux are
    /// invisible. `-i` is required: most setups export PATH from `.zshrc`.
    static let userPath: String = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l", "-i", "-c", "print -rn -- $PATH"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            let done = barrier(for: p)
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            done.wait()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                return path
            }
        } catch {}
        return ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    }()

    /// Never `Process.waitUntilExit()`: it pumps the run loop, which on the main
    /// thread lays out AppKit underneath a caller still on the stack.
    private static func barrier(for process: Process) -> DispatchSemaphore {
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        return done
    }

    static func findExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func which(_ name: String) -> String? {
        let r = run("/usr/bin/env", ["sh", "-c", "command -v \(name)"], env: ["PATH": userPath])
        guard r.status == 0 else { return nil }
        let out = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String],
                    env: [String: String]? = nil) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        var merged = ProcessInfo.processInfo.environment
        merged["PATH"] = userPath
        for (k, v) in env ?? [:] { merged[k] = v }
        p.environment = merged
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let done = barrier(for: p)
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        done.wait()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func runDetached(_ launchPath: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// pid → parent pid for every process on the machine, in one fork.
    static func processTree() -> [Int32: Int32] {
        let r = run("/bin/ps", ["-axo", "pid=,ppid="])
        guard r.status == 0 else { return [:] }
        var out: [Int32: Int32] = [:]
        for line in r.output.split(separator: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 2, let pid = Int32(f[0]), let ppid = Int32(f[1]) else { continue }
            out[pid] = ppid
        }
        return out
    }

    /// Listening TCP ports of the given pids, in one fork.
    ///
    /// `-a` is mandatory: lsof ORs its selection criteria, so without it this
    /// reports every listening socket on the machine and credits them all to us.
    static func listeningPorts(of pids: [Int32]) -> [Int32: [Int]] {
        guard !pids.isEmpty else { return [:] }
        let r = run("/usr/sbin/lsof",
                    ["-nP", "-a", "-p", pids.map(String.init).joined(separator: ","),
                     "-iTCP", "-sTCP:LISTEN", "-Fpn"])
        guard r.status == 0 else { return [:] }
        var out: [Int32: [Int]] = [:]
        var current: Int32?
        for line in r.output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            if tag == "p" {
                current = Int32(value)
            } else if tag == "n", let pid = current {
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...])
                else { continue }
                if !(out[pid]?.contains(port) ?? false) { out[pid, default: []].append(port) }
            }
        }
        return out
    }
}
