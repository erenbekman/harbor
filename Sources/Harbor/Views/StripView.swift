import SwiftUI
import AppKit

struct StripView: View {
    @ObservedObject var strip: Strip
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastDrag: CGFloat = 0
    @Namespace private var berth

    private var radius: CGFloat { strip.open ? 17 : 14 }

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
        return VisualEffect(material: .hudWindow, blending: .behindWindow)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.26), Color.white.opacity(0.07)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 18, x: -3, y: 8)
    }

    private var closed: some View {
        VStack(spacing: Strip.chipSpacing) {
            ForEach(store.projects) { project in
                VStack(spacing: 3) {
                    chip(project)
                        .matchedGeometryEffect(id: project.id, in: berth)
                    wake(project)
                }
                .frame(height: Strip.chipSlot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private func chip(_ project: Project) -> some View {
        let tint = Theme.tint(project.tint)
        let live = running(project) > 0
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return shape
            .fill(live ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.white.opacity(0.07)))
            .overlay(shape.strokeBorder(Color.white.opacity(live ? 0.18 : 0.1), lineWidth: 0.5))
            .frame(width: Strip.chipSize, height: Strip.chipSize)
            .overlay(
                Text(project.badge)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(live ? Color.white : tint)
            )
            .shadow(color: live ? tint.opacity(0.35) : .clear, radius: 6, y: 2)
    }

    private func wake(_ project: Project) -> some View {
        Wake(tint: Theme.tint(project.tint),
             visible: running(project) > 0,
             animated: !reduceMotion)
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            grip
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.projects.enumerated()), id: \.element.id) { index, project in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 0.5)
                                .padding(.horizontal, 12)
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
            Image(systemName: "sailboat")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(.tertiary)
            Text("nothing docked yet")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var grip: some View {
        Capsule()
            .fill(Color.white.opacity(0.22))
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
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.tint(project.tint))
                .frame(width: 8, height: 8)
                .matchedGeometryEffect(id: project.id, in: berth)
            Text(project.name)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if running(project) > 0 {
                Text("\(running(project))")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ServiceStatus.running.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(ServiceStatus.running.color.opacity(0.14)))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(folded ? -90 : 0))
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
        VStack(spacing: 1) {
            if project.services.isEmpty {
                HStack {
                    Text("no services")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 28)
                .frame(height: Strip.serviceHeight)
            }
            ForEach(project.services) { service in
                serviceRow(service, in: project)
            }
        }
        .padding(.bottom, 6)
    }

    private func serviceRow(_ service: Service, in project: Project) -> some View {
        let status = runner.status(of: service)
        let port = runner.port(of: service)
        return Button {
            runner.toggle(service, in: project)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: status.isLive ? "stop.fill" : "play.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(status.isLive ? Color.white : Color.white.opacity(0.75))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(status.isLive
                                      ? ServiceStatus.running.color.opacity(0.22)
                                      : Color.white.opacity(0.09))
                    )
                Text(service.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailing(status: status, port: port)
                    .id(trailingKey(status: status, port: port))
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .frame(height: Strip.serviceHeight - 1)
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
            Text(port.map { ":\($0)" } ?? "up")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ServiceStatus.running.color)
        case .starting:
            Circle().fill(ServiceStatus.starting.color).frame(width: 5, height: 5)
        case .failed(let code):
            Text(code.map { "exit \($0)" } ?? "exit")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ServiceStatus.failed(nil).color)
        case .stopped:
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private func trailingKey(status: ServiceStatus, port: Int?) -> String {
        "\(status)-\(port ?? 0)"
    }

    private func running(_ project: Project) -> Int {
        project.services.filter { runner.status(of: $0).isLive }.count
    }
}

private struct Wake: View {
    let tint: Color
    let visible: Bool
    let animated: Bool
    @State private var pulsing = false

    var body: some View {
        Capsule()
            .fill(tint)
            .frame(width: 14, height: 2)
            .opacity(visible ? (pulsing ? 1 : 0.45) : 0)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                       value: pulsing)
            .onAppear { pulsing = animated && visible }
            .onChange(of: visible) { _, now in pulsing = animated && now }
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0))
                    .padding(.horizontal, 6)
            )
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
