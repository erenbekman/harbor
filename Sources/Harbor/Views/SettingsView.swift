import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, about
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var icon: String { self == .general ? "gearshape" : "info.circle" }
    }

    @ObservedObject var strip: Strip
    @State private var section: Section = .general

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Section.allCases) { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(section == item ? Color.primary.opacity(0.09) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { section = item }
                }
                Spacer()
            }
            .padding(8)
            .frame(width: 168)
            .background(Theme.rail)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch section {
                    case .general: GeneralPane(strip: strip)
                    case .about: AboutPane()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.surface)
        }
        .frame(width: 640, height: 420)
    }
}

private struct GeneralPane: View {
    @ObservedObject var strip: Strip
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Text("General")
            .font(.system(size: 17, weight: .semibold))

        card {
            Toggle("Edge strip", isOn: Binding(
                get: { strip.installed },
                set: { strip.setEnabled($0) }
            ))
            Text("A column of project chips on the right edge of the screen, above every app. Hover it to see each project's services and start or stop them; drag it to move it up or down.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        card {
            Toggle("Open Harbor at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, wanted in apply(wanted) }
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(ServiceStatus.failed(nil).color)
            }
            Text("Services run in tmux, so quitting Harbor does not stop them. They are adopted again the next time it opens.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        card {
            row("Quick switcher", "⌃⌘H  ·  ⌘K in the app")
            row("Services", "one tmux session each, on \(Tmux.socketPath)")
        }
    }

    private func apply(_ wanted: Bool) {
        do {
            if wanted { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.separator.opacity(0.6), lineWidth: 1))
    }
}

private struct AboutPane: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Text("About")
            .font(.system(size: 17, weight: .semibold))

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Harbor")
                    .font(.system(size: 15, weight: .semibold))
                Text("A rail of projects, and every project's dev servers one click away.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)

            Divider()

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Version \(updater.currentVersion)")
                        .font(.system(size: 13, weight: .medium))
                    status
                }
                Spacer()
                action
            }
            .padding(14)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                row("Repository", "github.com/\(Updater.repository)")
                row("tmux", Tmux.path ?? "not installed")
                row("Support", Paths.support.path.replacingOccurrences(
                    of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
            }
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Theme.separator.opacity(0.6), lineWidth: 1))
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .idle:
            Text("Checked against the latest GitHub release.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
        case .checking:
            Text("Checking…").font(.system(size: 11)).foregroundStyle(Theme.secondary)
        case .upToDate:
            Text("You are on the latest version.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
        case .available(let version, _, let notes):
            VStack(alignment: .leading, spacing: 2) {
                Text("Version \(version) is available.")
                    .font(.system(size: 11)).foregroundStyle(ServiceStatus.running.color)
                if let line = notes.split(separator: "\n").first, !line.isEmpty {
                    Text(String(line))
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                }
            }
        case .downloading:
            Text("Downloading…").font(.system(size: 11)).foregroundStyle(Theme.secondary)
        case .installing:
            Text("Installing — Harbor will restart.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
        case .failed(let message):
            Text(message)
                .font(.system(size: 11)).foregroundStyle(ServiceStatus.failed(nil).color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch updater.state {
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        case .available(let version, _, _):
            Button("Update to \(version)") { updater.install() }
                .buttonStyle(.borderedProminent)
        default:
            Button("Check") { updater.check() }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
