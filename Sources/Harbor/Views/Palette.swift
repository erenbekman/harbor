import SwiftUI
import AppKit

/// Borderless panels do not become key on their own, and a switcher that cannot
/// take a keystroke is decoration.
final class PaletteWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct PaletteItem: Identifiable {
    enum Kind {
        case project(Project)
        case service(Project, Service)
    }

    let id: UUID
    let kind: Kind
    let title: String
    let subtitle: String
}

struct PaletteView: View {
    let close: () -> Void
    let reveal: (Project) -> Void
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner

    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Project or service…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .focused($focused)
                .onSubmit { run(items.indices.contains(index) ? items[index] : nil) }
                .onChange(of: query) { index = 0 }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                            row(item, selected: offset == index)
                                .id(item.id)
                                .onTapGesture { run(item) }
                        }
                    }
                    .padding(6)
                }
                .frame(height: 300)
                .onChange(of: index) {
                    guard items.indices.contains(index) else { return }
                    proxy.scrollTo(items[index].id)
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.separator, lineWidth: 1)
        )
        .onAppear { focused = true; index = 0 }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onExitCommand { close() }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            switch item.kind {
            case .project(let project):
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.tint(project.tint))
                    .frame(width: 10, height: 10)
            case .service(_, let service):
                Circle()
                    .fill(runner.status(of: service).color)
                    .frame(width: 10, height: 10)
            }
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
            Text(item.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
            if case .service(_, let service) = item.kind {
                Text(runner.status(of: service).isLive ? "stop" : "start")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .opacity(selected ? 1 : 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : .clear)
        )
        .contentShape(Rectangle())
    }

    private var items: [PaletteItem] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [PaletteItem] = []
        for project in store.projects {
            for service in project.services {
                let haystack = "\(project.name) \(service.name) \(service.command)".lowercased()
                guard needle.isEmpty || haystack.contains(needle) else { continue }
                out.append(PaletteItem(id: service.id, kind: .service(project, service),
                                       title: service.name, subtitle: project.name))
            }
        }
        for project in store.projects where needle.isEmpty || project.name.lowercased().contains(needle) {
            out.append(PaletteItem(id: project.id, kind: .project(project),
                                   title: project.name, subtitle: "open project"))
        }
        return out
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        index = max(0, min(items.count - 1, index + delta))
    }

    private func run(_ item: PaletteItem?) {
        guard let item else { return }
        switch item.kind {
        case .service(let project, let service):
            runner.toggle(service, in: project)
        case .project(let project):
            reveal(project)
        }
        close()
    }
}
