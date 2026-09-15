import SwiftUI
import AppKit

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
        VStack(alignment: .leading, spacing: 14) {
            Text(project == nil ? "Add project" : "Edit project")
                .font(.system(size: 15, weight: .semibold))

            Form {
                TextField("Name", text: $name)
                HStack(spacing: 6) {
                    TextField("Folder", text: $path)
                    Button("Choose…", action: choose)
                }
                LabeledContent("Color") {
                    HStack(spacing: 7) {
                        ForEach(Theme.tints.indices, id: \.self) { index in
                            Circle()
                                .fill(Theme.tint(index))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle().stroke(Color.primary.opacity(tint == index ? 0.85 : 0),
                                                    lineWidth: 2)
                                )
                                .onTapGesture { tint = index }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if !detected.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Services found in this folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                    ForEach(detected) { service in
                        Toggle(isOn: Binding(
                            get: { picked.contains(service.id) },
                            set: { on in
                                if on { picked.insert(service.id) } else { picked.remove(service.id) }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Text(service.name).font(.system(size: 12, weight: .medium))
                                Text(service.command)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(project == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || path.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
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
        VStack(alignment: .leading, spacing: 14) {
            Text(service == nil ? "Add service" : "Edit service")
                .font(.system(size: 15, weight: .semibold))

            Form {
                TextField("Name", text: $name, prompt: Text("dev"))
                TextField("Command", text: $command, prompt: Text("npm run dev"))
                    .font(.system(size: 12, design: .monospaced))
                TextField("Subfolder", text: $dir, prompt: Text("optional — e.g. frontend"))
                TextField("Health check", text: $health,
                          prompt: Text("optional — /health, or a full URL"))
                Toggle("Start automatically when Harbor opens", isOn: $autoStart)
                Toggle("Restart if it crashes", isOn: $autoRestart)
            }
            .formStyle(.grouped)

            Text("Runs in \(project.name) with your login shell, inside tmux — it keeps going when Harbor is closed.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(service == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
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
