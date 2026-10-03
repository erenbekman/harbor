import SwiftUI
import AppKit

struct ServicesPanel: View {
    let project: Project
    @Binding var sheet: ActiveSheet?
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @State private var expanded: Set<UUID> = []
    @State private var detected: [Service] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if project.services.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(project.services) { service in
                            ServiceRow(project: project,
                                       service: service,
                                       expanded: expanded.contains(service.id),
                                       toggleLog: { toggleLog(service) },
                                       edit: { sheet = .editService(project, service) })
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 17, weight: .semibold))
                Text(displayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .truncationMode(.head)
                    .lineLimit(1)
            }
            Spacer()
            Button { runner.startAll(in: project) } label: {
                Label("Start all", systemImage: "play.fill")
            }
            .disabled(project.services.isEmpty)
            Button { runner.stopAll(in: project) } label: {
                Label("Stop all", systemImage: "stop.fill")
            }
            .disabled(runningServices == 0)
            Button { sheet = .magic(project) } label: {
                Label("Magic", systemImage: "sparkles")
            }
            .help("Let Claude read the project and propose its services")
            Button { sheet = .newService(project) } label: {
                Image(systemName: "plus")
            }
            .help("Add service")
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No services for this project")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                Button("Add service") { sheet = .newService(project) }
                Button("Magic") { sheet = .magic(project) }
                if !detected.isEmpty {
                    Button("Add \(detected.count) detected") {
                        var copy = project
                        copy.services.append(contentsOf: detected)
                        store.update(copy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Off the render path: this reads the folder from disk.
        .onAppear { detected = Store.detectServices(at: project.path) }
    }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return project.path.hasPrefix(home)
            ? "~" + project.path.dropFirst(home.count)
            : project.path
    }

    private var runningServices: Int {
        project.services.filter { runner.status(of: $0).isLive }.count
    }

    private func toggleLog(_ service: Service) {
        if expanded.contains(service.id) { expanded.remove(service.id) }
        else { expanded.insert(service.id) }
    }
}

private struct ServiceRow: View {
    let project: Project
    let service: Service
    let expanded: Bool
    let toggleLog: () -> Void
    let edit: () -> Void

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner

    var body: some View {
        let status = runner.status(of: service)
        let port = runner.port(of: service)

        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Button { runner.toggle(service, in: project) } label: {
                    Image(systemName: status.isLive ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.separator.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .help(status.isLive ? "Stop" : "Start")

                VStack(alignment: .leading, spacing: 3) {
                    Text(service.name)
                        .font(.system(size: 13, weight: .medium))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 6, height: 6)
                        Text(status.label(port: port))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                    }
                }

                Spacer()

                if let port, status == .running {
                    Button {
                        NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondary)
                    .help("Open http://localhost:\(port)")
                }

                Button(action: toggleLog) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .buttonStyle(.plain)
                .help("Output")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if let conflict = runner.conflict(of: service) {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ServiceStatus.failed(nil).color)
                    Text(":\(conflict.port) is held by \(conflict.command) (\(conflict.pid))")
                        .font(.system(size: 11))
                    Spacer()
                    Button("Free port") { runner.freeConflict(service) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            if expanded {
                Divider()
                LogView(project: project, service: service)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.separator.opacity(0.6), lineWidth: 1)
        )
        .contextMenu {
            Button("Restart") { runner.restart(service, in: project) }
            Button("Open in Terminal") { Terminals.attach(session: project.session(for: service)) }
            Button("Edit…", action: edit)
            Divider()
            Button("Remove", role: .destructive) {
                runner.stop(service, in: project)
                store.removeService(service, from: project)
            }
        }
    }
}

private struct LogView: View {
    let project: Project
    let service: Service
    @EnvironmentObject private var runner: Runner
    @State private var text = ""

    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "— no output —" : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .id("bottom")
            }
            .frame(height: 190)
            .onAppear {
                refresh { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onReceive(tick) { _ in
                refresh { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private func refresh(_ done: @escaping () -> Void) {
        runner.log(service, in: project) { output in
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != text { text = trimmed }
            done()
        }
    }
}
