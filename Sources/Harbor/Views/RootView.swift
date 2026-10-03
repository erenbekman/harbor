import SwiftUI
import AppKit

enum ActiveSheet: Identifiable {
    case newProject
    case editProject(Project)
    case newService(Project)
    case magic(Project)
    case editService(Project, Service)

    var id: String {
        switch self {
        case .newProject: return "new-project"
        case .editProject(let p): return "edit-project-\(p.id)"
        case .newService(let p): return "new-service-\(p.id)"
        case .magic(let p): return "magic-\(p.id)"
        case .editService(_, let s): return "edit-service-\(s.id)"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @State private var sheet: ActiveSheet?

    var body: some View {
        HStack(spacing: 0) {
            ProjectRail(sheet: $sheet)
            Divider()
            Group {
                if let project = store.selected {
                    ServicesPanel(project: project, sheet: $sheet)
                        .id(project.id)
                } else {
                    EmptyProjects { sheet = .newProject }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
        }
        .frame(minWidth: 640, minHeight: 440)
        .sheet(item: $sheet) { item in
            switch item {
            case .newProject:
                ProjectSheet(project: nil)
            case .editProject(let project):
                ProjectSheet(project: project)
            case .newService(let project):
                ServiceSheet(project: project, service: nil)
            case .magic(let project):
                MagicSheet(project: project)
            case .editService(let project, let service):
                ServiceSheet(project: project, service: service)
            }
        }
    }
}

private struct EmptyProjects: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.secondary)
            Text("No projects yet")
                .font(.system(size: 15, weight: .medium))
            Text("Add a folder and Harbor keeps its dev servers one click away.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Add project", action: add)
                .controlSize(.large)
        }
    }
}

struct ProjectRail: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @Binding var sheet: ActiveSheet?

    @AppStorage("railExpanded") private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: expanded ? 1 : 6) {
                    ForEach(store.projects) { project in
                        ProjectRow(project: project,
                                   expanded: expanded,
                                   selected: store.selection == project.id,
                                   running: runningCount(project))
                            .onTapGesture { store.selection = project.id }
                            .contextMenu {
                                Button("Edit…") { sheet = .editProject(project) }
                                Button("Open in Editor") { Terminals.openInEditor(path: project.path) }
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
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

                    Button { sheet = .newProject } label: {
                        if expanded {
                            HStack(spacing: 9) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 10)
                                Text("Add project")
                                    .font(.system(size: 13))
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                        } else {
                            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                .fill(Theme.separator.opacity(0.35))
                                .frame(width: Theme.chipSize, height: Theme.chipSize)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(Theme.secondary)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Add project")
                }
                .padding(.vertical, 12)
            }

            Divider()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    if expanded {
                        Text("Collapse")
                            .font(.system(size: 11))
                        Spacer(minLength: 0)
                    }
                }
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
                .padding(.horizontal, expanded ? 16 : 0)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Collapse to icons" : "Show project names")
        }
        .frame(width: expanded ? Theme.railExpandedWidth : Theme.railWidth)
        .background(Theme.rail)
    }

    private func runningCount(_ project: Project) -> Int {
        project.services.filter { runner.status(of: $0).isLive }.count
    }

    private func move(_ project: Project, by delta: Int) {
        guard let index = store.projects.firstIndex(where: { $0.id == project.id }) else { return }
        store.move(project, to: index + delta)
    }
}

/// Two rails, one row. Expanded it is the project's NAME — with a name on screen
/// a badge of its initials says nothing, so the chip shrinks to the colour it was
/// carrying. Collapsed, the colour is all there is, so the chip comes back.
private struct ProjectRow: View {
    let project: Project
    let expanded: Bool
    let selected: Bool
    let running: Int

    var body: some View {
        Group { expanded ? AnyView(nameRow) : AnyView(chipRow) }
            .contentShape(Rectangle())
            .help(expanded ? "" : project.name)
            .animation(.easeOut(duration: 0.15), value: selected)
    }

    private var nameRow: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.tint(project.tint))
                .frame(width: 10, height: 10)
                .opacity(selected ? 1 : 0.75)
            Text(project.name)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if running > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(ServiceStatus.running.color)
                        .frame(width: 6, height: 6)
                    if running > 1 {
                        Text("\(running)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.08) : .clear)
        )
        .padding(.horizontal, 6)
    }

    private var chipRow: some View {
        let tint = Theme.tint(project.tint)
        return RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .fill(selected ? tint : tint.opacity(0.16))
            .frame(width: Theme.chipSize, height: Theme.chipSize)
            .overlay(
                Text(project.badge)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Color.white : tint)
            )
            .overlay(alignment: .topTrailing) {
                if running > 0 {
                    Circle()
                        .fill(ServiceStatus.running.color)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Theme.rail, lineWidth: 2))
                        .offset(x: 3, y: -3)
                }
            }
    }
}
