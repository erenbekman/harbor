import SwiftUI
import AppKit

struct StripView: View {
    @ObservedObject var strip: Strip
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @State private var lastDrag: CGFloat = 0

    private var radius: CGFloat { strip.open ? 22 : 19 }

    var body: some View {
        Group {
            if strip.open { expandedBody } else { closed }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(glass)
        // The card floats; the window underneath still reaches the screen edge.
        .padding(.trailing, Strip.edgeInset)
    }

    private var glass: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, x: -2, y: 6)
    }

    /// Closed: one chip per project, with its initials — something to aim at,
    /// and enough to tell the projects apart without opening anything.
    private var closed: some View {
        VStack(spacing: Strip.chipSpacing) {
            ForEach(store.projects) { project in
                let tint = Theme.tint(project.tint)
                let live = running(project) > 0
                Circle()
                    .fill(live ? tint : tint.opacity(0.26))
                    .frame(width: Strip.chipSize, height: Strip.chipSize)
                    .overlay(
                        Text(project.badge)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(live ? Color.white : tint)
                    )
                    .overlay(alignment: .topTrailing) {
                        if live {
                            Circle()
                                .fill(ServiceStatus.running.color)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1.5))
                                .offset(x: 1, y: -1)
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
            .fill(Color.white.opacity(0.25))
            .frame(width: 28, height: 4)
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
        HStack(spacing: 9) {
            Circle()
                .fill(Theme.tint(project.tint))
                .frame(width: 9, height: 9)
            Text(project.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            if running(project) > 0 {
                Text("\(running(project))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ServiceStatus.running.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(ServiceStatus.running.color.opacity(0.18)))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(strip.collapsed.contains(project.id) ? -90 : 0))
        }
        .padding(.horizontal, 12)
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
        VStack(spacing: 2) {
            if project.services.isEmpty {
                Text("no services")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(height: Strip.serviceHeight)
            }
            ForEach(project.services) { service in
                let status = runner.status(of: service)
                HStack(spacing: 9) {
                    Button { runner.toggle(service, in: project) } label: {
                        Image(systemName: status.isLive ? "stop.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(status.isLive ? 0.22 : 0.12)))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(service.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(status.label(port: runner.port(of: service)))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                }
                .padding(.horizontal, 10)
                .frame(height: Strip.serviceHeight - 2)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 6)
    }

    private func running(_ project: Project) -> Int {
        project.services.filter { runner.status(of: $0).isLive }.count
    }
}
