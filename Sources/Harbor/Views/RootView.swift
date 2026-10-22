import SwiftUI
import AppKit

enum ActiveSheet: Identifiable {
    case newProject
    case editProject(Project)
    case newService(Project)
    case editService(Project, Service)
    case magic(Project)

    var id: String {
        switch self {
        case .newProject: return "new-project"
        case .editProject(let p): return "edit-project-\(p.id)"
        case .newService(let p): return "new-service-\(p.id)"
        case .editService(_, let s): return "edit-service-\(s.id)"
        case .magic(let p): return "magic-\(p.id)"
        }
    }
}

struct ProjectSidebar: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner

    var body: some View {
        List(selection: Binding(
            get: { store.selection },
            set: { store.selection = $0 }
        )) {
            ForEach(store.projects) { project in
                row(project).tag(project.id)
            }
            .onMove { from, to in store.move(from: from, to: to) }
        }
        .listStyle(.sidebar)
        .tint(Theme.accent)
        .scrollContentBackground(.hidden)
        .background(Theme.base)
        .environment(\.defaultMinListRowHeight, 26)
        .overlay {
            if store.projects.isEmpty {
                Text("No projects")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                Button { store.requested = .newProject } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("Add project")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.muted)
                    .frame(height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(.bar)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
        }
    }

    private func row(_ project: Project) -> some View {
        let live = project.services.filter { runner.status(of: $0).isLive }.count
        return HStack(spacing: 7) {
            Circle()
                .fill(Theme.tint(project.tint))
                .frame(width: 8, height: 8)
            Text(project.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if live > 0 {
                Text("\(live)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.line))
            }
        }
        .contextMenu {
            Button("Edit…") { store.requested = .editProject(project) }
            Button { Terminals.openInEditor(path: project.path) } label: {
                Label("Open in Editor", systemImage: "arrow.up.right")
            }
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
            } label: {
                Label("Reveal in Finder", systemImage: "arrow.up.right")
            }
            Divider()
            Button("Move up") { move(project, by: -1) }
            Button("Move down") { move(project, by: 1) }
            Divider()
            Button("Remove", role: .destructive) {
                runner.stopAll(in: project)
                store.remove(project)
            }
        }
    }

    private func move(_ project: Project, by delta: Int) {
        guard let index = store.projects.firstIndex(where: { $0.id == project.id }) else { return }
        store.move(project, to: index + delta)
    }
}

struct DetailContainer: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @State private var sheet: ActiveSheet?

    var body: some View {
        Group {
            if let project = store.selected {
                ServicesPanel(project: project, sheet: $sheet).id(project.id)
            } else {
                EmptyProjects { sheet = .newProject }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
        .background(ContentPlane())
        .onChange(of: store.requested) { _, action in
            guard let action else { return }
            store.requested = nil
            switch action {
            case .newProject: sheet = .newProject
            case .editProject(let project): sheet = .editProject(project)
            case .newService: if let project = store.selected { sheet = .newService(project) }
            case .magic: if let project = store.selected { sheet = .magic(project) }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .newProject:
                ProjectSheet(project: nil)
            case .editProject(let project):
                ProjectSheet(project: project)
            case .newService(let project):
                ServiceSheet(project: project, service: nil)
            case .editService(let project, let service):
                ServiceSheet(project: project, service: service)
            case .magic(let project):
                MagicSheet(project: project)
            }
        }
    }
}

private struct ContentPlane: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .contentBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct EmptyProjects: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: Mark.image(size: 34, filled: false))
                .foregroundStyle(.tertiary)
            Text("No projects yet")
                .font(.system(size: 15, weight: .medium))
            Text("Add a folder and Harbor keeps its dev servers one click away.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button("Add project", action: add)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
