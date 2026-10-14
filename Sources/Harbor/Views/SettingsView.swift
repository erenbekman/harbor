import SwiftUI
import ServiceManagement
import AppKit

struct GeneralSettings: View {
    @ObservedObject var strip: Strip
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Harbor at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, wanted in apply(wanted) }
                Toggle("Show the edge strip", isOn: Binding(
                    get: { strip.installed },
                    set: { strip.setEnabled($0) }
                ))
            } footer: {
                Text("The strip is a column of project chips on the right edge of the screen, above every app. Hover it to start or stop a service without leaving what you are doing.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let error {
                Section {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
            }

            Section {
                LabeledContent("Quick switcher", value: "⌃⌘H")
                LabeledContent("Quick switcher in Harbor", value: "⌘K")
            } header: {
                Text("Shortcuts")
            }

            Section {
                LabeledContent("Run in", value: "tmux")
                LabeledContent("Socket", value: Tmux.socketPath)
            } header: {
                Text("Services")
            } footer: {
                Text("Services keep running when Harbor quits, and are adopted again the next time it opens.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 430)
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
}

struct AboutSettings: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Harbor")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Your projects' dev servers, one click away.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Version") {
                    HStack(spacing: 10) {
                        status
                        action
                    }
                }
            }

            Section {
                LabeledContent("Repository", value: "github.com/\(Updater.repository)")
                LabeledContent("tmux", value: Tmux.path ?? "not installed")
                LabeledContent("Support", value: Paths.support.path.replacingOccurrences(
                    of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 430)
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .idle, .checking:
            Text(updater.currentVersion).foregroundStyle(.secondary)
        case .upToDate:
            Text("\(updater.currentVersion) — up to date").foregroundStyle(.secondary)
        case .available(let version, _, _):
            Text("\(updater.currentVersion) — \(version) available")
                .foregroundStyle(ServiceStatus.running.color)
        case .downloading:
            Text("Downloading…").foregroundStyle(.secondary)
        case .installing:
            Text("Installing — Harbor will restart.").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(Color(nsColor: .systemRed))
        }
    }

    @ViewBuilder
    private var action: some View {
        switch updater.state {
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        case .available(let version, _, _):
            Button { updater.install() } label: {
                Label("Update to \(version)", systemImage: "arrow.down.circle")
            }
        default:
            Button("Check") { updater.check() }
        }
    }
}
