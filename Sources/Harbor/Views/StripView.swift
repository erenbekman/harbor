import SwiftUI
import AppKit

struct StripView: View {
    @ObservedObject var strip: Strip
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @State private var lastDrag: CGFloat = 0

    var body: some View {
        Group {
            if strip.open { expandedBody } else { closed }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(.rect(topLeadingRadius: 12, bottomLeadingRadius: 12))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .stroke(Theme.separator.opacity(0.7), lineWidth: 1)
        )
    }

    /// Closed: one chip per project, with its initials — something to aim at,
    /// and enough to tell the projects apart without opening anything.
    private var closed: some View {
        VStack(spacing: Strip.chipSpacing) {
            ForEach(store.projects) { project in
                let tint = Theme.tint(project.tint)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(running(project) > 0 ? 1 : 0.22))
                    .frame(width: Strip.chipSize, height: Strip.chipSize)
                    .overlay(
                        Text(project.badge)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(running(project) > 0 ? Color.white : tint)
                    )
                    .overlay(alignment: .topTrailing) {
                        if running(project) > 0 {
                            Circle()
                                .fill(ServiceStatus.running.color)
                                .frame(width: 7, height: 7)
                                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                                .offset(x: 2, y: -2)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            grip
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.projects) { project in
                        projectRow(project)
                        if !strip.collapsed.contains(project.id) {
                            services(of: project)
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.vertical, Strip.padding)
    }

    /// The strip is dragged by this, never by its rows — a row is a button.
    private var grip: some View {
        Capsule()
            .fill(Theme.secondary.opacity(0.35))
            .frame(width: 26, height: 3)
            .frame(maxWidth: .infinity)
            .frame(height: Strip.gripHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .help("Drag to move")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                // Global coordinates grow downwards; the screen's grow upwards.
                strip.move(by: -(value.translation.height - lastDrag))
                lastDrag = value.translation.height
            }
            .onEnded { _ in
                lastDrag = 0
                strip.rememberPosition()
            }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.tint(project.tint))
                .frame(width: 9, height: 9)
            Text(project.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            if running(project) > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(ServiceStatus.running.color)
                        .frame(width: 5, height: 5)
                    Text("\(running(project))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .rotationEffect(.degrees(strip.collapsed.contains(project.id) ? 0 : 90))
        }
        .padding(.horizontal, 10)
        .frame(height: Strip.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                strip.openInWindow(project)
            } else {
                strip.toggle(project)
            }
        }
        .help("⌘-click to open in Harbor")
    }

    @ViewBuilder
    private func services(of project: Project) -> some View {
        VStack(spacing: 0) {
            if project.services.isEmpty {
                Text("no services")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .frame(height: Strip.serviceHeight)
            }
            ForEach(project.services) { service in
                let status = runner.status(of: service)
                HStack(spacing: 8) {
                    Button { runner.toggle(service, in: project) } label: {
                        Image(systemName: status.isLive ? "stop.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.separator.opacity(0.35)))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(service.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text(status.label(port: runner.port(of: service)))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Circle()
                        .fill(status.color)
                        .frame(width: 5, height: 5)
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(height: Strip.serviceHeight)
            }
        }
        .padding(.bottom, 6)
    }

    private func running(_ project: Project) -> Int {
        project.services.filter { runner.status(of: $0).isLive }.count
    }
}
