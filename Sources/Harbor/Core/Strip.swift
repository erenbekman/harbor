import AppKit
import Combine
import SwiftUI

/// The edge strip: the only surface that belongs to no window, which is the
/// point — you want to see what is running while you are in the editor, not in
/// Harbor. It sits as a sliver on the right edge and opens when the pointer
/// reaches it.
@MainActor
final class Strip: ObservableObject {
    static let width: CGFloat = 200
    /// Closed, the strip is a column of project chips: a 6pt line was easy to
    /// miss and impossible to aim at.
    static let closedWidth: CGFloat = 44
    static let chipSize: CGFloat = 30
    static let chipSpacing: CGFloat = 7
    static let rowHeight: CGFloat = 30
    static let serviceHeight: CGFloat = 32
    static let padding: CGFloat = 8
    static let gripHeight: CGFloat = 13

    @Published private(set) var installed = false
    @Published private(set) var open = false
    /// Open, every project lists its services — that is the whole reason to
    /// look. A project can still be folded away, and it stays folded.
    @Published private(set) var collapsed: Set<UUID> = []
    /// Where the strip sits on the right edge, as a fraction of the screen, so
    /// it keeps its place when the panel grows or the display changes.
    private var centerFraction: CGFloat =
        UserDefaults.standard.object(forKey: "stripCenter") as? Double ?? 0.5

    var onOpenProject: ((Project) -> Void)?

    private let store: Store
    private let runner: Runner
    private var panel: StripPanel?
    private var hideTask: Task<Void, Never>?
    private var watch: AnyCancellable?

    init(store: Store, runner: Runner) {
        self.store = store
        self.runner = runner
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "stripEnabled") as? Bool ?? true
    }

    /// The one place the preference and the panel are kept in step — the menu
    /// bar item and Settings both come through here.
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "stripEnabled")
        if enabled { install() } else { remove() }
    }

    func install() {
        guard panel == nil else { return }

        let hosting = FirstMouseHostingView(rootView: AnyView(
            StripView(strip: self).environmentObject(store).environmentObject(runner)
        ))
        hosting.autoresizingMask = [.width, .height]

        let container = HoverView()
        container.onEnter = { [weak self] in self?.hoverBegan() }
        container.onExit = { [weak self] in self?.hoverEnded() }
        hosting.frame = container.bounds
        container.addSubview(hosting)

        let panel = StripPanel(contentRect: frame(open: false),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.orderFrontRegardless()
        self.panel = panel
        installed = true

        // Adding or removing a project changes the height the panel must have,
        // and `objectWillChange` fires BEFORE the change lands.
        watch = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
    }

    func remove() {
        watch = nil
        hideTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
        open = false
        installed = false
    }

    func toggle(_ project: Project) {
        if collapsed.contains(project.id) { collapsed.remove(project.id) }
        else { collapsed.insert(project.id) }
        layout()
    }

    func openInWindow(_ project: Project) {
        setOpen(false)
        onOpenProject?(project)
    }

    // MARK: - Moving

    /// Dragged by its grip; `delta` is in screen points, positive upwards.
    func move(by delta: CGFloat) {
        guard let panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame,
              visible.height > 0 else { return }
        let height = panel.frame.height
        let lowest = visible.minY + height / 2
        let highest = visible.maxY - height / 2
        let current = visible.minY + centerFraction * visible.height
        let wanted = min(max(current + delta, min(lowest, highest)), max(lowest, highest))
        centerFraction = (wanted - visible.minY) / visible.height
        panel.setFrame(frame(open: open), display: true)
    }

    func rememberPosition() {
        UserDefaults.standard.set(Double(centerFraction), forKey: "stripCenter")
    }

    // MARK: - Hover

    private func hoverBegan() {
        hideTask?.cancel()
        setOpen(true)
    }

    private func hoverEnded() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.setOpen(false)
        }
    }

    private func setOpen(_ value: Bool) {
        guard open != value else { return }
        open = value
        layout()
    }

    // MARK: - Geometry

    /// Heights are ARITHMETIC: AppKit animates the window frame and has to know
    /// the total before SwiftUI lays anything out.
    private var openHeight: CGFloat {
        var height = Self.padding * 2 + Self.gripHeight
        for project in store.projects {
            height += Self.rowHeight
            guard !collapsed.contains(project.id) else { continue }
            height += CGFloat(max(project.services.count, 1)) * Self.serviceHeight + 6
        }
        let ceiling = ((panel?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) - 24
        return min(max(height, 70), ceiling)
    }

    private var closedHeight: CGFloat {
        let count = CGFloat(max(store.projects.count, 1))
        return Self.padding * 2 + count * Self.chipSize + (count - 1) * Self.chipSpacing
    }

    private func frame(open: Bool) -> NSRect {
        let screen = panel?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }
        let width = open ? Self.width : Self.closedWidth
        let height = open ? openHeight : closedHeight
        let center = visible.minY + centerFraction * visible.height
        let clamped = min(max(center, visible.minY + height / 2), visible.maxY - height / 2)
        return NSRect(x: visible.maxX - width,
                      y: clamped - height / 2,
                      width: width, height: height)
    }

    private func layout() {
        guard let panel else { return }
        let target = frame(open: open)
        guard target != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        }
    }
}

final class StripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A panel that is never key would otherwise spend the first click on trying to
/// activate itself, and the button under the pointer would not fire.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// `.activeAlways`, never SwiftUI's `onHover`: the panel is never key, and the
/// only time the strip matters is when another application is in front.
final class HoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
