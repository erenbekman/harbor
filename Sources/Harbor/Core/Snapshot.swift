import Foundation

struct ServiceState: Sendable {
    var status: ServiceStatus
    var port: Int?
    var conflict: PortConflict?
    var origin: String?
}

enum Snapshot {
    struct Target: Sendable {
        let id: UUID
        let session: String
        let service: Service
    }

    static func take(_ targets: [Target], alreadyFailed: Set<UUID> = []) async -> [UUID: ServiceState] {
        let panes = Tmux.paneStates()
        var states: [UUID: ServiceState] = [:]
        var livePids: [UUID: Int32] = [:]

        for target in targets {
            guard let pane = panes[target.session] else {
                states[target.id] = ServiceState(status: .stopped, port: nil, conflict: nil, origin: nil)
                continue
            }
            if pane.dead {
                states[target.id] = ServiceState(status: .failed(pane.exitCode), port: nil,
                                                 conflict: nil, origin: pane.origin)
            } else {
                states[target.id] = ServiceState(status: .running, port: nil,
                                                 conflict: nil, origin: pane.origin)
                livePids[target.id] = pane.pid
            }
        }

        if !livePids.isEmpty {
            var children: [Int32: [Int32]] = [:]
            for (pid, parent) in Shell.processTree() { children[parent, default: []].append(pid) }
            var owner: [Int32: UUID] = [:]
            var descendants: [Int32] = []
            for (id, pid) in livePids {
                var stack = [pid]
                while let next = stack.popLast() {
                    guard owner[next] == nil else { continue }
                    owner[next] = id
                    descendants.append(next)
                    stack += children[next] ?? []
                }
            }
            for (pid, list) in Shell.listeningPorts(of: descendants) {
                guard let id = owner[pid], let port = list.min() else { continue }
                let current = states[id]?.port
                states[id]?.port = min(current ?? port, port)
            }
        }

        for target in targets where !target.service.health.isEmpty {
            guard states[target.id]?.status == .running else { continue }
            guard let url = target.service.healthURL(port: states[target.id]?.port) else {
                states[target.id]?.status = .starting
                continue
            }
            if await !probe(url) { states[target.id]?.status = .starting }
        }

        for target in targets {
            guard case .failed = states[target.id]?.status, !alreadyFailed.contains(target.id) else { continue }
            guard let port = portInUse(inOutputOf: target.session),
                  let holder = Terminals.holder(ofPort: port) else { continue }
            states[target.id]?.conflict = PortConflict(port: port, pid: holder.pid, command: holder.command)
        }

        return states
    }

    static func probe(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 500) < 400
        } catch {
            return false
        }
    }

    static func portInUse(inOutputOf session: String) -> Int? {
        let output = strippingANSI(Tmux.capture(session, lines: 80)).lowercased()
        guard let line = output.split(separator: "\n").last(where: {
            $0.contains("eaddrinuse") || $0.contains("already in use") || $0.contains("address in use")
        }) else { return nil }
        guard let regex = try? NSRegularExpression(pattern: "(?::|port\\s+)(\\d{2,5})") else { return nil }
        let text = String(line)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last, let range = Range(last.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    static func strippingANSI(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[a-zA-Z]") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
