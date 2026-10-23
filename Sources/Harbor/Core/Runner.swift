import Foundation

@MainActor
final class Runner: ObservableObject {
    @Published private(set) var status: [UUID: ServiceStatus] = [:]
    @Published private(set) var ports: [UUID: Int] = [:]
    @Published private(set) var conflicts: [UUID: PortConflict] = [:]
    @Published private(set) var origins: [UUID: String] = [:]

    weak var store: Store?
    private var timer: Timer?
    private var startedAt: [UUID: Date] = [:]
    private var restarts: [UUID: Int] = [:]

    private static let restartLimit = 3

    func startPolling() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func status(of service: Service) -> ServiceStatus { status[service.id] ?? .stopped }
    func port(of service: Service) -> Int? { ports[service.id] }
    func conflict(of service: Service) -> PortConflict? { conflicts[service.id] }
    func origin(of service: Service) -> String? { origins[service.id] }

    var runningCount: Int { status.values.filter { $0.isLive }.count }

    // MARK: - Control

    func start(_ service: Service, in project: Project) {
        guard status(of: service) != .running else { return }
        status[service.id] = .starting
        startedAt[service.id] = Date()
        conflicts[service.id] = nil
        let session = project.session(for: service)
        let cwd = service.resolvedCwd(projectPath: project.path)
        let command = service.command
        Task.detached(priority: .userInitiated) {
            // A live pane is ADOPTED, never restarted: auto-start on launch must
            // not kill the dev server that was already running.
            if let state = Tmux.paneState(session) {
                if !state.dead { return }
                Tmux.kill(session)
            }
            Tmux.start(session: session, cwd: cwd, command: command)
            Tmux.markOrigin(session, nil)
        }
    }

    func stop(_ service: Service, in project: Project) {
        status[service.id] = .stopped
        startedAt[service.id] = nil
        ports[service.id] = nil
        restarts[service.id] = 0
        let session = project.session(for: service)
        Task.detached(priority: .userInitiated) {
            Tmux.interrupt(session)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            Tmux.kill(session)
        }
    }

    func toggle(_ service: Service, in project: Project) {
        if status(of: service).isLive { stop(service, in: project) } else { start(service, in: project) }
    }

    func restart(_ service: Service, in project: Project) {
        let session = project.session(for: service)
        let cwd = service.resolvedCwd(projectPath: project.path)
        let command = service.command
        status[service.id] = .starting
        startedAt[service.id] = Date()
        conflicts[service.id] = nil
        Task.detached(priority: .userInitiated) {
            Tmux.interrupt(session)
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            Tmux.kill(session)
            Tmux.start(session: session, cwd: cwd, command: command)
            Tmux.markOrigin(session, nil)
        }
    }

    func startAll(in project: Project) {
        for service in project.services { start(service, in: project) }
    }

    func stopAll(in project: Project) {
        for service in project.services { stop(service, in: project) }
    }

    /// Everything marked "start automatically", at launch. `start` adopts a live
    /// pane, so a service left running from the last session is not disturbed.
    func startAutoServices() {
        for project in store?.projects ?? [] {
            for service in project.services where service.autoStart {
                start(service, in: project)
            }
        }
    }

    func freeConflict(_ service: Service) {
        guard let conflict = conflicts[service.id] else { return }
        Terminals.free(pid: conflict.pid)
        conflicts[service.id] = nil
    }

    func log(_ service: Service, in project: Project, completion: @escaping (String) -> Void) {
        let session = project.session(for: service)
        Task.detached(priority: .utility) {
            let text = Snapshot.strippingANSI(Tmux.capture(session, lines: 300))
            await MainActor.run { completion(text) }
        }
    }

    // MARK: - Poll

    private func poll() {
        let targets: [Snapshot.Target] = (store?.projects ?? []).flatMap { project in
            project.services.map { Snapshot.Target(id: $0.id, session: project.session(for: $0), service: $0) }
        }
        guard !targets.isEmpty || !status.isEmpty else { return }
        let alreadyFailed = Set(status.filter { if case .failed = $0.value { return true } else { return false } }
                                      .map(\.key))

        Task.detached(priority: .utility) {
            let states = await Snapshot.take(targets, alreadyFailed: alreadyFailed)
            await MainActor.run { self.apply(states) }
        }
    }

    private func apply(_ states: [UUID: ServiceState]) {
        var nextStatus: [UUID: ServiceStatus] = [:]
        var nextPorts: [UUID: Int] = [:]
        var nextConflicts: [UUID: PortConflict] = [:]
        var nextOrigins: [UUID: String] = [:]
        for (id, state) in states {
            nextStatus[id] = state.status
            if let port = state.port { nextPorts[id] = port }
            if let conflict = state.conflict { nextConflicts[id] = conflict }
            if let origin = state.origin { nextOrigins[id] = origin }
        }
        if nextOrigins != origins { origins = nextOrigins }
        apply(status: nextStatus, ports: nextPorts, conflicts: nextConflicts)
    }

    /// Never publish an unchanged value: an `@Published` write invalidates every
    /// view that reads it, and this runs every two seconds forever.
    private func apply(status next: [UUID: ServiceStatus],
                       ports nextPorts: [UUID: Int],
                       conflicts nextConflicts: [UUID: PortConflict]) {
        // A pane takes a moment to appear; without this the row blinks back to
        // "stopped" between the click and the first poll that sees the session.
        var merged = next
        for (id, value) in status where value == .starting && next[id] == .stopped {
            guard let since = startedAt[id], Date().timeIntervalSince(since) < 10 else { continue }
            merged[id] = .starting
        }

        for (id, value) in merged {
            guard case .failed(let code) = value else { continue }
            guard status[id] != value, !isFailed(status[id]) else { continue }
            announce(id: id, exit: code)
        }

        if merged != status { status = merged }
        if nextPorts != ports { ports = nextPorts }
        var mergedConflicts = conflicts.filter { isFailed(merged[$0.key]) }
        for (id, conflict) in nextConflicts { mergedConflicts[id] = conflict }
        if mergedConflicts != conflicts { conflicts = mergedConflicts }
    }

    private func isFailed(_ status: ServiceStatus?) -> Bool {
        if case .failed = status { return true }
        return false
    }

    private func announce(id: UUID, exit code: Int?) {
        guard let store,
              let project = store.projects.first(where: { $0.services.contains { $0.id == id } }),
              let service = project.services.first(where: { $0.id == id })
        else { return }
        guard code != 0 else { return }

        let attempts = restarts[id] ?? 0
        if service.autoRestart && attempts < Self.restartLimit {
            restarts[id] = attempts + 1
            Notify.post(title: "\(project.name) · \(service.name) crashed",
                        message: "exit \(code.map(String.init) ?? "?") — restarting (\(attempts + 1)/\(Self.restartLimit))")
            let target = service
            let owner = project
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.restart(target, in: owner)
            }
        } else {
            Notify.post(title: "\(project.name) · \(service.name) stopped",
                        message: "exit \(code.map(String.init) ?? "?")")
        }
    }

    // MARK: - Probes

    /// The port a dead service was complaining about. Every runtime words it
    /// differently — EADDRINUSE, "address already in use", "Port 3000 is already
    /// in use" — so the line is found first and the number read out of it.

}
