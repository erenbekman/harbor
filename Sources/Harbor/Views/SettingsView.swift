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
                AgentsRow()
            } header: {
                Text("Coding agents")
            } footer: {
                Text("Claude Code and Codex can list, start, stop and read the logs of the services you registered here — nothing else. They cannot add a service, run a command of their own, or kill a process. Allow mcp__harbor__list_services and mcp__harbor__read_logs without asking; leave starting and stopping to a prompt.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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

private struct AgentsRow: View {
    @State private var registered: Bool?
    @State private var message = ""
    @State private var working = false

    private var command: String {
        Bundle.main.executableURL?.path ?? Bundle.main.bundlePath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Claude Code") {
                HStack(spacing: 10) {
                    Text(registered == true ? "Connected" : registered == false ? "Not connected" : "…")
                        .foregroundStyle(.secondary)
                    Button(registered == true ? "Re-add" : "Add to Claude Code") { add() }
                        .disabled(working)
                }
            }

            LabeledContent("Codex") {
                Button("Copy config") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(codexConfig, forType: .string)
                    message = "Codex config copied — paste it into ~/.codex/config.toml."
                }
            }

            if !Bundle.main.bundlePath.hasPrefix("/Applications/") {
                Text("Harbor is running from \(Bundle.main.bundlePath). The agent will be pointed at that copy.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { check() }
    }

    private var codexConfig: String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "[mcp_servers.harbor]\ncommand = \"\(escaped)\"\nargs = [\"mcp\"]"
    }

    private func check() {
        let expected = command
        Task.detached {
            let result = Shell.run("/bin/zsh", ["-l", "-c", "claude mcp get harbor"], timeout: 20)
            let exists = result.status == 0
            let matches = exists && result.output.contains(expected)
            await MainActor.run {
                registered = matches
                if exists, !matches {
                    message = "Claude Code has a harbor server registered, but it points at another copy. Re-add it to point it here."
                }
            }
        }
    }

    private func add() {
        working = true
        message = ""
        let quoted = Shell.quoted(command)
        Task.detached {
            let result = Shell.run("/bin/zsh",
                                   ["-l", "-c", "claude mcp remove --scope user harbor >/dev/null 2>&1; "
                                    + "claude mcp add --scope user harbor -- \(quoted) mcp"],
                                   timeout: 30)
            let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                working = false
                message = result.status == 0
                    ? "Added. Restart Claude Code to pick it up."
                    : (text.isEmpty ? "Could not add it — is the claude command installed?" : text)
                check()
            }
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
