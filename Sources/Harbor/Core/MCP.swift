import Foundation

enum MCP {
    private static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    static func run() {
        setvbuf(stdout, nil, _IOLBF, 0)
        Tmux.ensureConfig()
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                emit(["jsonrpc": "2.0", "id": NSNull(),
                      "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            handle(message)
        }
    }

    private static func handle(_ message: [String: Any]) {
        let method = message["method"] as? String ?? ""
        let id = message["id"]

        switch method {
        case "initialize":
            let params = message["params"] as? [String: Any] ?? [:]
            let asked = params["protocolVersion"] as? String
            let version = asked.flatMap { protocolVersions.contains($0) ? $0 : nil } ?? protocolVersions[0]
            reply(id, [
                "protocolVersion": version,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "harbor", "version": appVersion],
            ])
        case "notifications/initialized", "notifications/cancelled":
            return
        case "ping":
            reply(id, [String: Any]())
        case "tools/list":
            reply(id, ["tools": tools])
        case "tools/call":
            guard id != nil else { return }
            let params = message["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard !name.isEmpty else {
                fail(id, -32602, "A tool name is required.")
                return
            }
            let outcome = call(name, arguments)
            reply(id, ["content": [["type": "text", "text": outcome.text]], "isError": outcome.failed])
        default:
            guard id != nil else { return }
            fail(id, -32601, "Unknown method: \(method)")
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    // MARK: - Tools

    private static var tools: [[String: Any]] {
        let project: [String: Any] = [
            "type": "string",
            "description": "Project name or folder path. Defaults to the project whose folder contains the working directory.",
        ]
        let service: [String: Any] = ["type": "string", "description": "Service name, exactly as registered in Harbor."]

        return [
            [
                "name": "list_services",
                "description": "List the dev services a project has registered in Harbor, with their status, port and URL. Use this before starting anything: it shows what already runs.",
                "inputSchema": ["type": "object", "properties": ["project": project]],
            ],
            [
                "name": "start_service",
                "description": "Start one registered service and wait until it is listening or has failed. Use this instead of starting dev servers yourself in the background — Harbor keeps them in tmux, where the user sees them too. Only services the user registered can be started.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "service": service, "project": project,
                        "wait_seconds": ["type": "integer", "description": "How long to wait for it to come up. Default 20, max 120."],
                    ],
                    "required": ["service"],
                ],
            ],
            [
                "name": "stop_service",
                "description": "Stop one registered service. This stops only Harbor's own tmux session for that service — never kill processes by name or port yourself.",
                "inputSchema": ["type": "object", "properties": ["service": service, "project": project],
                                "required": ["service"]],
            ],
            [
                "name": "restart_service",
                "description": "Restart one registered service and wait for it to come back.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["service": service, "project": project,
                                   "wait_seconds": ["type": "integer", "description": "Default 20, max 120."]],
                    "required": ["service"],
                ],
            ],
            [
                "name": "read_logs",
                "description": "Read a service's recent output straight from its tmux pane — the same text the user sees in Harbor.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "service": service, "project": project,
                        "lines": ["type": "integer", "description": "How many trailing lines. Default 200, max 2000."],
                        "contains": ["type": "string", "description": "Plain substring filter; matching lines with two lines of context."],
                    ],
                    "required": ["service"],
                ],
            ],
        ]
    }

    private static func call(_ name: String, _ arguments: [String: Any]) -> (text: String, failed: Bool) {
        do {
            switch name {
            case "list_services": return (try listServices(arguments), false)
            case "start_service": return (try startService(arguments, restart: false), false)
            case "restart_service": return (try startService(arguments, restart: true), false)
            case "stop_service": return (try stopService(arguments), false)
            case "read_logs": return (try readLogs(arguments), false)
            default: return ("Unknown tool: \(name)", true)
            }
        } catch let error as Failure {
            return (error.message, true)
        } catch {
            return (error.localizedDescription, true)
        }
    }

    private struct Failure: Error { let message: String }

    // MARK: - Resolution

    private static func projects() throws -> [Project] {
        guard let data = try? Data(contentsOf: Paths.projectsFile) else { return [] }
        guard let list = try? JSONDecoder().decode([Project].self, from: data) else {
            throw Failure(message: "Harbor's project list at \(Paths.projectsFile.path) exists but could not be read. "
                          + "Do not ask the user to add the project again — that would overwrite it. "
                          + "Ask them to check that file.")
        }
        return list
    }

    private static func project(_ arguments: [String: Any]) throws -> Project {
        let all = try projects()
        guard !all.isEmpty else {
            throw Failure(message: "Harbor has no projects yet. Ask the user to add this folder to Harbor.")
        }
        if let wanted = (arguments["project"] as? String)?.trimmingCharacters(in: .whitespaces), !wanted.isEmpty {
            let expanded = canonical((wanted as NSString).expandingTildeInPath)
            if let match = all.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame })
                ?? all.first(where: { canonical($0.path) == expanded }) {
                return match
            }
            throw Failure(message: "No project called \(wanted). Harbor knows: "
                          + all.map(\.name).joined(separator: ", "))
        }
        let cwd = canonical(FileManager.default.currentDirectoryPath)
        let containing = all
            .filter { cwd == canonical($0.path) || cwd.hasPrefix(canonical($0.path) + "/") }
            .max { $0.path.count < $1.path.count }
        if let containing { return containing }
        throw Failure(message: "This folder is not registered in Harbor. Ask the user to add it, or name one of: "
                      + all.map(\.name).joined(separator: ", "))
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func service(_ arguments: [String: Any], in project: Project) throws -> Service {
        let wanted = (arguments["service"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { throw Failure(message: "A service name is required.") }
        if let match = project.services.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame })
            ?? project.services.first(where: { $0.id.uuidString.caseInsensitiveCompare(wanted) == .orderedSame }) {
            return match
        }
        let known = project.services.map(\.name).joined(separator: ", ")
        throw Failure(message: "\(project.name) has no service called \(wanted)."
                      + (known.isEmpty ? " It has none registered yet; ask the user to add one in Harbor."
                                       : " It has: \(known). Ask the user to add it in Harbor if it is missing."))
    }

    private static func state(_ service: Service, in project: Project) throws -> ServiceState {
        let target = Snapshot.Target(id: service.id, session: project.session(for: service), service: service)
        let states = try sync { await Snapshot.take([target]) }
        return states[service.id] ?? ServiceState(status: .stopped, port: nil, conflict: nil, origin: nil)
    }

    private static let readTimeout: TimeInterval = 15

    private static func sync<T: Sendable>(_ body: @escaping @Sendable () async -> T) throws -> T {
        let group = DispatchGroup()
        group.enter()
        let box = Box<T>()
        Task.detached {
            box.value = await body()
            group.leave()
        }
        guard group.wait(timeout: .now() + readTimeout) == .success, let value = box.value else {
            throw Failure(message: "Harbor could not read the service state within \(Int(readTimeout))s: "
                          + "tmux or lsof is not answering.")
        }
        return value
    }

    private final class Box<T>: @unchecked Sendable { var value: T? }

    // MARK: - Handlers

    private static func describe(_ service: Service, _ state: ServiceState, origin: String?) -> [String: Any] {
        var row: [String: Any] = [
            "name": service.name,
            "command": service.command,
            "status": word(state.status),
            "started_by": origin == "agent" ? "agent" : "user",
        ]
        if case .failed(let code) = state.status, let code { row["exit_code"] = code }
        if let port = state.port {
            row["port"] = port
            row["url"] = "http://localhost:\(port)"
        }
        if !service.health.isEmpty { row["health"] = service.health }
        if !service.dir.isEmpty { row["dir"] = service.dir }
        if let conflict = state.conflict {
            row["port_conflict"] = ["port": conflict.port, "held_by": conflict.command, "pid": Int(conflict.pid)]
        }
        return row
    }

    private static func word(_ status: ServiceStatus) -> String {
        switch status {
        case .running: return "running"
        case .starting: return "starting"
        case .stopped: return "stopped"
        case .failed: return "failed"
        }
    }

    private static func listServices(_ arguments: [String: Any]) throws -> String {
        let project = try project(arguments)
        let targets = project.services.map {
            Snapshot.Target(id: $0.id, session: project.session(for: $0), service: $0)
        }
        let states = try sync { await Snapshot.take(targets) }
        let rows = project.services.map { service -> [String: Any] in
            let state = states[service.id] ?? ServiceState(status: .stopped, port: nil, conflict: nil, origin: nil)
            return describe(service, state, origin: state.origin)
        }
        return json(["project": project.name, "path": project.path, "services": rows])
    }

    private static func startService(_ arguments: [String: Any], restart: Bool) throws -> String {
        let project = try project(arguments)
        let service = try service(arguments, in: project)
        let session = project.session(for: service)
        let cwd = service.resolvedCwd(projectPath: project.path)

        if restart {
            Tmux.interrupt(session)
            Thread.sleep(forTimeInterval: 1.4)
            Tmux.kill(session)
            Tmux.start(session: session, cwd: cwd, command: service.command)
            Tmux.markOrigin(session, "agent")
        } else if let pane = Tmux.paneState(session) {
            if pane.dead {
                Tmux.kill(session)
                Tmux.start(session: session, cwd: cwd, command: service.command)
                Tmux.markOrigin(session, "agent")
            }
        } else {
            Tmux.start(session: session, cwd: cwd, command: service.command)
            Tmux.markOrigin(session, "agent")
        }

        let budget = min(max((arguments["wait_seconds"] as? Int) ?? 20, 0), 120)
        var state = try state(service, in: project)
        var waited = 0
        while waited < budget {
            if case .failed = state.status { break }
            if state.status == .running { break }
            Thread.sleep(forTimeInterval: 1)
            waited += 1
            state = try self.state(service, in: project)
        }

        var result = describe(service, state, origin: state.origin)
        result["waited_seconds"] = waited
        result["recent_output"] = tail(session, lines: 40)
        return json(result)
    }

    private static func stopService(_ arguments: [String: Any]) throws -> String {
        let project = try project(arguments)
        let service = try service(arguments, in: project)
        let session = project.session(for: service)
        Tmux.interrupt(session)
        Thread.sleep(forTimeInterval: 1.2)
        Tmux.kill(session)
        let state = try state(service, in: project)
        return json(describe(service, state, origin: nil))
    }

    private static func readLogs(_ arguments: [String: Any]) throws -> String {
        let project = try project(arguments)
        let service = try service(arguments, in: project)
        let lines = min(max((arguments["lines"] as? Int) ?? 200, 1), 2000)
        var text = tail(project.session(for: service), lines: lines)

        if let needle = (arguments["contains"] as? String), !needle.isEmpty {
            let all = text.components(separatedBy: "\n")
            var keep = Set<Int>()
            for (index, line) in all.enumerated() where line.localizedCaseInsensitiveContains(needle) {
                for offset in -2...2 where all.indices.contains(index + offset) { keep.insert(index + offset) }
            }
            text = keep.sorted().map { all[$0] }.joined(separator: "\n")
            if text.isEmpty { text = "No line contains \(needle)." }
        }

        return json(["service": service.name, "project": project.name, "output": text])
    }

    private static func tail(_ session: String, lines: Int) -> String {
        Snapshot.strippingANSI(Tmux.capture(session, lines: lines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Transport

    private static func reply(_ id: Any?, _ result: [String: Any]) {
        guard let id else { return }
        emit(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func fail(_ id: Any?, _ code: Int, _ message: String) {
        emit(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    private static func emit(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
