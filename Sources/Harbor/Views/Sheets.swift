import SwiftUI
import AppKit

private struct FieldBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.faint)
            HStack(spacing: 8) { content }
        }
    }
}

private struct SheetFrame<Content: View, Actions: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 14) { content }
            Divider().opacity(0.6)
            HStack(spacing: 8) {
                Spacer()
                actions
            }
        }
        .padding(22)
        .background(Theme.raised)
    }
}

struct ProjectSheet: View {
    let project: Project?
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var path = ""
    @State private var tint = 0
    @State private var detected: [Service] = []
    @State private var picked: Set<UUID> = []

    var body: some View {
        SheetFrame(title: project == nil ? "Add project" : "Edit project") {
            FormRow(label: "Name") {
                FieldBox {
                    TextField("", text: $name, prompt: Text("nott"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
            }
            FormRow(label: "Folder") {
                FieldBox {
                    TextField("", text: $path, prompt: Text("~/Documents/GitHub/nott"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                Button("Choose…", action: choose)
                    .controlSize(.small)
            }
            FormRow(label: "Color") {
                HStack(spacing: 7) {
                    ForEach(Theme.tints.indices, id: \.self) { index in
                        Circle()
                            .fill(Theme.tint(index))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle().stroke(Color.primary.opacity(tint == index ? 0.9 : 0), lineWidth: 2)
                                    .padding(-3)
                            )
                            .onTapGesture { tint = index }
                    }
                }
                .frame(height: 26)
            }

            if !detected.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Found in this folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    ForEach(detected) { service in
                        Toggle(isOn: Binding(
                            get: { picked.contains(service.id) },
                            set: { on in
                                if on { picked.insert(service.id) } else { picked.remove(service.id) }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Text(service.name).font(.system(size: 12))
                                Text(service.command)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.faint)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.top, 2)
            }
        } actions: {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(project == nil ? "Add" : "Save", action: save)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || path.isEmpty)
        }
        .frame(width: 470)
        .onAppear {
            if let project {
                name = project.name
                path = project.path
                tint = project.tint
            } else {
                tint = store.projects.count % Theme.tints.count
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = url.lastPathComponent }
        if project == nil {
            detected = Store.detectServices(at: url.path)
            picked = Set(detected.map(\.id))
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if var project {
            project.name = trimmedName
            project.path = path
            project.tint = tint
            store.update(project)
        } else {
            let services = detected.filter { picked.contains($0.id) }
            store.add(Project(name: trimmedName, path: path, tint: tint, services: services))
        }
        dismiss()
    }
}

struct ServiceSheet: View {
    let project: Project
    let service: Service?
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var command = ""
    @State private var dir = ""
    @State private var autoStart = false
    @State private var autoRestart = false
    @State private var health = ""

    var body: some View {
        SheetFrame(title: service == nil ? "Add service" : "Edit service") {
            FormRow(label: "Name") {
                FieldBox {
                    TextField("", text: $name, prompt: Text("dev"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
            }
            FormRow(label: "Command") {
                FieldBox {
                    TextField("", text: $command, prompt: Text("npm run dev"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            FormRow(label: "Subfolder") {
                FieldBox {
                    TextField("", text: $dir, prompt: Text("optional — frontend"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
            }
            FormRow(label: "Health check") {
                FieldBox {
                    TextField("", text: $health, prompt: Text("optional — /health"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
            }

            Divider().opacity(0.6).padding(.vertical, 2)

            Toggle("Start automatically when Harbor opens", isOn: $autoStart)
            Toggle("Restart if it crashes", isOn: $autoRestart)

            Text("Runs in \(project.name) through your login shell, inside tmux — it keeps going when Harbor is closed.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(service == nil ? "Add" : "Save", action: save)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || command.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(width: 470)
        .onAppear {
            guard let service else { return }
            name = service.name
            command = service.command
            dir = service.dir
            autoStart = service.autoStart
            autoRestart = service.autoRestart
            health = service.health
        }
    }

    private func save() {
        var edited = service ?? Service(name: "", command: "")
        edited.name = name.trimmingCharacters(in: .whitespaces)
        edited.command = command.trimmingCharacters(in: .whitespaces)
        edited.dir = dir.trimmingCharacters(in: .whitespaces)
        edited.autoStart = autoStart
        edited.autoRestart = autoRestart
        edited.health = health.trimmingCharacters(in: .whitespaces)
        store.upsert(edited, in: project)
        dismiss()
    }
}
