import SwiftUI
import AppKit

struct StripView: View {
    @ObservedObject var strip: Strip
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastDrag: CGFloat = 0
    @Namespace private var berth

    private var radius: CGFloat { strip.open ? 12 : 11 }

    var body: some View {
        Group {
            if strip.open { expandedBody } else { closed }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panel)
        .padding(.trailing, Strip.edgeInset)
        .animation(reduceMotion ? .linear(duration: 0.12)
                                : .spring(response: 0.3, dampingFraction: 0.85),
                   value: strip.open)
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return VisualEffect(material: .popover, blending: .behindWindow)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 14, x: -2, y: 6)
    }

    private var closed: some View {
        VStack(spacing: Strip.chipSpacing) {
            ForEach(store.projects) { project in
                chip(project)
                    .matchedGeometryEffect(id: project.id, in: berth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private func chip(_ project: Project) -> some View {
        let live = running(project) > 0
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(live ? Theme.control : Theme.hover)
            .frame(width: Strip.chipSize, height: Strip.chipSize)
            .overlay(
                Text(project.badge)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(live ? Theme.ink : Theme.muted)
            )
            .overlay(alignment: .topTrailing) {
                if live {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: -2)
                }
            }
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            grip
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                        if index > 0 {
                            Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 12)
                        }
                        VStack(spacing: 0) {
                            projectRow(project)
                            if !strip.collapsed.contains(project.id) {
                                services(of: project)
                            }
                        }
                        .modifier(Arrival(step: index, enabled: !reduceMotion))
                    }
                    if store.projects.isEmpty { empty }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.vertical, Strip.padding)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(nsImage: Mark.image(size: 20, filled: false))
                .foregroundStyle(Theme.muted)
            Text("No projects yet")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var grip: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 24, height: 3)
            .frame(maxWidth: .infinity)
            .frame(height: Strip.gripHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .help("Drag to move")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                strip.move(by: -(value.translation.height - lastDrag))
                lastDrag = value.translation.height
            }
            .onEnded { _ in
                lastDrag = 0
                strip.rememberPosition()
            }
    }

    private func projectRow(_ project: Project) -> some View {
        let folded = strip.collapsed.contains(project.id)
        let live = running(project)
        return HStack(spacing: 8) {
            Text(project.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if live > 0 {
                Text("\(live) running")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            Image(systemName: "arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.faint)
                .rotationEffect(.degrees(folded ? 0 : 180))
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
        VStack(spacing: 0) {
            if project.services.isEmpty {
                HStack {
                    Text("No services")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 33)
                .frame(height: Strip.serviceHeight)
            }
            ForEach(project.services) { service in
                serviceRow(service, in: project)
            }
        }
        .padding(.bottom, 4)
    }

    private func serviceRow(_ service: Service, in project: Project) -> some View {
        let status = runner.status(of: service)
        let port = runner.port(of: service)
        return Button {
            runner.toggle(service, in: project)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: status.isLive ? "stop.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(status.isLive ? Theme.ink : Theme.muted)
                    .frame(width: 13)
                Text(service.name)
                    .font(.system(size: 12))
                    .foregroundStyle(status.isLive ? Theme.ink : Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailing(status: status, port: port)
                    .id(trailingKey(status: status, port: port))
                    .transition(.opacity)
            }
            .padding(.horizontal, 12)
            .frame(height: Strip.serviceHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(StripRowStyle())
        .animation(reduceMotion ? .linear(duration: 0.1) : .easeOut(duration: 0.25),
                   value: trailingKey(status: status, port: port))
    }

    @ViewBuilder
    private func trailing(status: ServiceStatus, port: Int?) -> some View {
        switch status {
        case .running:
            Text(port.map { ":\($0)" } ?? "running")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(ServiceStatus.running.color)
        case .starting:
            Text("starting")
                .font(.system(size: 11))
                .foregroundStyle(ServiceStatus.starting.color)
        case .failed(let code):
            Text(code.map { "exit \($0)" } ?? "exited")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(ServiceStatus.failed(nil).color)
        case .stopped:
            Text("stopped")
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
        }
    }

    private func trailingKey(status: ServiceStatus, port: Int?) -> String {
        "\(status)-\(port ?? 0)"
    }

    private func running(_ project: Project) -> Int {
        project.services.filter { runner.status(of: $0).isLive }.count
    }
}

private struct Arrival: ViewModifier {
    let step: Int
    let enabled: Bool
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived ? 0 : -6)
            .onAppear {
                guard enabled else { arrived = true; return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)
                    .delay(Double(step) * 0.028)) {
                    arrived = true
                }
            }
    }
}

private struct StripRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.accent.opacity(configuration.isPressed ? 0.3 : 0))
    }
}

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
