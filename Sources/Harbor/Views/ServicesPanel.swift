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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if project.services.isEmpty {
                    emptyState
                } else {
                    group(title: "Services", trailing: runningLabel) {
                        ForEach(Array(project.services.enumerated()), id: \.element.id) { index, service in
                            if index > 0 { rowDivider }
                            ServiceRow(project: project,
                                       service: service,
                                       expanded: expanded.contains(service.id),
                                       toggleLog: { toggleLog(service) },
                                       edit: { sheet = .editService(project, service) })
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear { detected = Store.detectServices(at: project.path) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(project.name)
                .font(.system(size: 17, weight: .semibold))
            PathControl(url: URL(fileURLWithPath: project.path))
                .frame(height: 20)
                .padding(.leading, -4)
        }
    }

    private var runningLabel: String? {
        guard !project.services.isEmpty else { return nil }
        return runningServices > 0 ? "\(runningServices) of \(project.services.count) running" : nil
    }

    @ViewBuilder
    private func group<Content: View>(title: String, trailing: String? = nil,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .background(Theme.raised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 38)
    }

    private var emptyState: some View {
        group(title: "Services") {
            VStack(spacing: 10) {
                Text("No services for this project")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
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
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    private var runningServices: Int {
        project.services.filter { runner.status(of: $0).isLive }.count
    }

    private func toggleLog(_ service: Service) {
        if expanded.contains(service.id) { expanded.remove(service.id) }
        else { expanded.insert(service.id) }
    }
}

private struct PathControl: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSPathControl {
        let control = NSPathControl()
        control.pathStyle = .standard
        control.isEditable = false
        control.focusRingType = .none
        control.font = .systemFont(ofSize: 11)
        control.target = context.coordinator
        control.action = #selector(Coordinator.clicked(_:))
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSPathControl, context: Context) {
        control.url = url
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        @objc func clicked(_ sender: NSPathControl) {
            guard let target = sender.clickedPathItem?.url ?? sender.url else { return }
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
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
            HStack(spacing: 10) {
                Button { runner.toggle(service, in: project) } label: {
                    Image(systemName: status.isLive ? "stop.fill" : "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(status.isLive ? Theme.ink : Theme.muted)
                        .frame(width: 18, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(status.isLive ? "Stop" : "Start")

                Text(service.name)
                    .font(.system(size: 13))

                Text(service.command)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if let port, status == .running {
                    Button {
                        NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!)
                    } label: {
                        HStack(spacing: 3) {
                            Text(":\(port)")
                                .font(.system(size: 12).monospacedDigit())
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Open http://localhost:\(port)")
                } else if status != .stopped {
                    Text(statusLabel(status))
                        .font(.system(size: 12))
                        .foregroundStyle(status.color)
                }

                Button(action: toggleLog) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted.opacity(0.8))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 18, height: 22)
                        .contentShape(Rectangle())
                }
                .help(expanded ? "Hide output" : "Show output")
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)

            if let conflict = runner.conflict(of: service) {
                Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 38)
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ServiceStatus.failed(nil).color)
                    Text(":\(conflict.port) is held by \(conflict.command) (\(conflict.pid))")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Free port") { runner.freeConflict(service) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
            }

            if expanded {
                Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 38)
                LogView(project: project, service: service)
            }
        }
        .contextMenu {
            Button("Restart") { runner.restart(service, in: project) }
            Button { Terminals.attach(session: project.session(for: service)) } label: {
                Label("Open in Terminal", systemImage: "arrow.up.right")
            }
            Button("Edit…", action: edit)
            Divider()
            Button("Remove", role: .destructive) {
                runner.stop(service, in: project)
                store.removeService(service, from: project)
            }
        }
    }

    private func statusLabel(_ status: ServiceStatus) -> String {
        switch status {
        case .running: return "running"
        case .starting: return "starting"
        case .stopped: return "stopped"
        case .failed(let code): return code.map { "exit \($0)" } ?? "exited"
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
            .onAppear { refresh { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onReceive(tick) { _ in refresh { proxy.scrollTo("bottom", anchor: .bottom) } }
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
