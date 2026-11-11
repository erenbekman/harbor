import SwiftUI
import AppKit

struct StripView: View {
    @ObservedObject var strip: Strip
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var runner: Runner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastDrag: CGFloat = 0

    private var focused: Project? {
        store.projects.first { $0.id == strip.focus } ?? store.projects.first
    }

    var body: some View {
        HStack(spacing: 0) {
            if strip.open, let project = focused {
                card(project)
                    .frame(width: Strip.cardWidth + Strip.tailWidth)
                    .offset(y: strip.cardOffset)
                    .transition(.scale(scale: 0.88, anchor: strip.tailAnchor)
                        .combined(with: .opacity))
            }
            VStack(spacing: Strip.buttonGap) {
                rail
                appButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .animation(reduceMotion ? .linear(duration: 0.12)
                                : .spring(response: 0.26, dampingFraction: 0.88),
                   value: strip.open)
        .animation(reduceMotion ? .linear(duration: 0.1)
                                : .spring(response: 0.3, dampingFraction: 0.86),
                   value: strip.focus)
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(spacing: Strip.tileSpacing) {
            if store.projects.isEmpty {
                emptyTile
            } else {
                ForEach(store.projects) { tile($0) }
            }
        }
        .padding(.vertical, Strip.railInset)
        .frame(width: Strip.railWidth)
        .padding(.vertical, Strip.flare)
        .background(
            EdgePanel(flare: Strip.flare, corner: Strip.innerCorner)
                .fill(Theme.shell)
                .shadow(color: .black.opacity(0.3), radius: 12, x: -3, y: 0)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
    }

    private func tile(_ project: Project) -> some View {
        let live = running(project)
        let total = project.services.count
        let selected = strip.open && focused?.id == project.id
        return VStack(spacing: Strip.labelGap) {
            ZStack {
                Circle().fill(Color.white.opacity(selected ? 0.13 : 0.06))
                Circle().stroke(Color.white.opacity(0.1), lineWidth: Strip.ringWidth)
                Circle()
                    .trim(from: 0, to: progress(project))
                    .stroke(ring(project),
                            style: StrokeStyle(lineWidth: Strip.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(project.badge)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(live > 0 ? Color.white : Theme.muted)
            }
            .frame(width: Strip.ringSize, height: Strip.ringSize)
            .scaleEffect(selected ? 1.06 : 1)
            Text(total == 0 ? "—" : "\(live)/\(total)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(selected ? 0.75 : 0.5))
                .frame(height: Strip.labelHeight)
        }
        .contentShape(Rectangle())
        .onTapGesture { strip.openInWindow(project) }
        .help("\(project.name) — click to open in Harbor")
    }

    private var emptyTile: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.06))
            Image(nsImage: Mark.image(size: 18, filled: false)).foregroundStyle(Theme.faint)
        }
        .frame(width: Strip.ringSize, height: Strip.ringSize)
        .frame(height: Strip.tileHeight)
        .help("No projects yet")
    }

    private var appButton: some View {
        Circle()
            .fill(Theme.shell)
            .frame(width: Strip.buttonSize, height: Strip.buttonSize)
            .overlay(
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
            )
            .shadow(color: .black.opacity(0.3), radius: 10, x: -2, y: 2)
            .frame(width: Strip.railWidth)
            .contentShape(Circle())
            .onTapGesture { strip.openApp() }
            .help("Open Harbor")
    }

    private func progress(_ project: Project) -> CGFloat {
        guard !project.services.isEmpty else { return 0 }
        if project.services.contains(where: { if case .failed = runner.status(of: $0) { return true } else { return false } }) {
            return 1
        }
        return CGFloat(running(project)) / CGFloat(project.services.count)
    }

    private func ring(_ project: Project) -> Color {
        if project.services.contains(where: { if case .failed = runner.status(of: $0) { return true } else { return false } }) {
            return Color(nsColor: .systemRed)
        }
        if project.services.contains(where: { runner.status(of: $0) == .starting }) {
            return Color(nsColor: .systemOrange)
        }
        return running(project) > 0 ? Color(nsColor: .systemGreen) : Color.white.opacity(0.2)
    }

    // MARK: - Card

    private func card(_ project: Project) -> some View {
        VStack(spacing: 0) {
            header(project)
            if project.services.isEmpty {
                HStack {
                    Text("No services")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: Strip.serviceHeight)
            }
            ForEach(project.services) { serviceRow($0, in: project) }
        }
        .padding(.vertical, Strip.cardPadding)
        .padding(.trailing, Strip.tailWidth)
        .background(callout)
    }

    private var callout: some View {
        let shape = Callout(radius: Strip.cardCorner,
                            tailWidth: Strip.tailWidth,
                            tailHeight: Strip.tailHeight,
                            tailCenter: strip.tailCenter)
        return shape
            .fill(Theme.raised)
            .overlay(shape.stroke(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 18, x: -4, y: 8)
    }

    private func header(_ project: Project) -> some View {
        let live = running(project)
        return HStack(spacing: 8) {
            Text(project.name.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(live > 0 ? "\(live) running" : "idle")
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 12)
        .frame(height: Strip.headerHeight)
        .contentShape(Rectangle())
        .onTapGesture { strip.openInWindow(project) }
        .help("Open in Harbor")
    }

    private func serviceRow(_ service: Service, in project: Project) -> some View {
        let status = runner.status(of: service)
        let port = runner.port(of: service)
        return HStack(spacing: 10) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(service.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if status.isLive, runner.origin(of: service) == "agent" {
                        Text("agent")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Theme.badgeInk)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 0.5)
                            .background(Capsule().fill(Theme.badge))
                    }
                }
                Text(trailing(status, port))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button { runner.toggle(service, in: project) } label: {
                Image(systemName: status.isLive ? "stop.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(status.isLive ? Theme.ink : Theme.muted)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(status.isLive ? "Stop" : "Start")
        }
        .padding(.horizontal, 12)
        .frame(height: Strip.serviceHeight)
        .help(service.command)
    }

    // MARK: - Bits

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                strip.move(by: -(value.translation.height - lastDrag))
                lastDrag = value.translation.height
            }
            .onEnded { _ in
                lastDrag = 0
                strip.rememberPosition()
            }
    }

    private func trailing(_ status: ServiceStatus, _ port: Int?) -> String {
        switch status {
        case .running: return port.map { "running · :\($0)" } ?? "running"
        case .starting: return "starting"
        case .stopped: return "stopped"
        case .failed(let code): return code.map { "exit \($0)" } ?? "exited"
        }
    }

    private func running(_ project: Project) -> Int {
        project.services.filter { runner.status(of: $0).isLive }.count
    }
}

private struct EdgePanel: Shape {
    var flare: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY + flare,
                          width: rect.width, height: max(rect.height - flare * 2, 1))
        let r = min(corner, body.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - flare, y: body.minY))
        path.addArc(center: CGPoint(x: body.maxX - flare, y: body.minY - flare),
                    radius: flare, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY + flare))
        path.addArc(center: CGPoint(x: body.maxX - flare, y: body.maxY + flare),
                    radius: flare, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                    tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                    tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

private struct Callout: Shape {
    var radius: CGFloat
    var tailWidth: CGFloat
    var tailHeight: CGFloat
    var tailCenter: CGFloat

    var animatableData: CGFloat {
        get { tailCenter }
        set { tailCenter = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY,
                          width: max(rect.width - tailWidth, 1), height: rect.height)
        let r = min(radius, min(body.width, body.height) / 2)
        let y = min(max(tailCenter, body.minY + r + tailHeight / 2),
                    body.maxY - r - tailHeight / 2)
        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                    tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        path.addLine(to: CGPoint(x: body.maxX, y: y - tailHeight / 2))
        path.addLine(to: CGPoint(x: body.maxX + tailWidth, y: y))
        path.addLine(to: CGPoint(x: body.maxX, y: y + tailHeight / 2))
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                    tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                    tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                    tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }
}
