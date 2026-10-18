import SwiftUI
import AppKit

struct ServicesPanel: View {
    let project: Project
    @Binding var sheet: ActiveSheet?
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @State private var expanded: Set<UUID> = []
    @State private var detected: [Service] = []
    @State private var hovered: UUID?
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                sectionLabel
                if project.services.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, service in
                        if index > 0 {
                            Rectangle().fill(Theme.line).frame(height: 0.5)
                        }
                        ServiceRow(project: project,
                                   service: service,
                                   expanded: expanded.contains(service.id),
                                   hovered: hovered == service.id,
                                   toggleLog: { toggleLog(service) },
                                   edit: { sheet = .editService(project, service) })
                            .onHover { inside in hovered = inside ? service.id : (hovered == service.id ? nil : hovered) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .onAppear { detected = Store.detectServices(at: project.path) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(project.name)
                .font(.system(size: 19, weight: .semibold))
            PathControl(url: URL(fileURLWithPath: project.path))
                .frame(height: 18)
                .padding(.leading, -4)
                .opacity(0.85)
        }
        .padding(.bottom, 20)
    }

    private var sectionLabel: some View {
        HStack(spacing: 8) {
            Text("Services")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Spacer()
            if project.services.count >= 5 {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                    TextField("Filter", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 96)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.raised))
            }
            if let runningLabel {
                Text(runningLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.bottom, 6)
    }

    private var visible: [Service] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return project.services }
        return project.services.filter {
            $0.name.lowercased().contains(needle) || $0.command.lowercased().contains(needle)
        }
    }

    private var runningLabel: String? {
        guard !project.services.isEmpty, runningServices > 0 else { return nil }
        return "\(runningServices) of \(project.services.count) running"
    }

    private var emptyState: some View {
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
        .padding(.vertical, 26)
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
        control.font = .systemFont(ofSize: 10)
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
    let hovered: Bool
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
                        .frame(width: 16, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(status.isLive ? "Stop" : "Start")

                Text(service.name)
                    .font(.system(size: 13))

                Text(service.command)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
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
                        .foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 16, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(expanded ? "Hide output" : "Show output")
                .opacity(hovered || expanded ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered ? Theme.hover : .clear)
            )

            if let conflict = runner.conflict(of: service) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ServiceStatus.failed(nil).color)
                    Text(":\(conflict.port) is held by \(conflict.command) (\(conflict.pid))")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Free port") { confirmFree(conflict) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
            }

            if expanded {
                LogView(project: project, service: service)
                    .background(Theme.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.bottom, 6)
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

    private func confirmFree(_ conflict: PortConflict) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Stop \(conflict.command) (\(conflict.pid))?"
        alert.informativeText = "It is holding port \(conflict.port). Harbor did not start this process, and stopping it may lose unsaved work."
        alert.addButton(withTitle: "Stop it")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runner.freeConflict(service)
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
